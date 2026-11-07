#!/usr/bin/env bash
#
# Resolve the latest web release of each Craft app and record it in versions.json.
# The file is rewritten only when something changed, so the scheduled workflow can
# commit it (keeping the repository active) and trigger the Pages deployment.
#
# Most apps publish a <app>-web-*.zip asset. VibeOffice is plain static HTML/JS
# with no web zip, so its release source archive is pinned instead and its
# public/ directory is published.
#
# Usage: scripts/check-versions.sh
#
# Environment:
#   GH_TOKEN     token for the GitHub API (recommended, avoids rate limits)
#   SOURCE_ORG   GitHub owner of the storytold apps (default: storytold)
#
# Under GitHub Actions, sets the step output "changed" to true or false.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${SOURCE_ORG:-storytold}"
API="https://api.github.com"
VERSIONS="$ROOT/versions.json"
APPS=(
  wordcraft photocraft deckcraft gridcraft
  pdfcraft lightcraft filmcraft cadcraft soundcraft materialcraft
  designcraft texturecraft figcraft vectorcraft effectcraft
  vibeoffice
)

for tool in curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' is required but was not found in PATH" >&2
    exit 1
  fi
done

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
  -H "User-Agent: web-tools-pages"
)
if [[ -n "${GH_TOKEN:-}" ]]; then
  api_headers+=(-H "Authorization: Bearer $GH_TOKEN")
fi

repo_for() {
  case "$1" in
    vibeoffice) echo "tcchen2026/VibeOffice" ;;
    *) echo "$ORG/$1" ;;
  esac
}

: > "$WORK/apps.jsonl"

for app in "${APPS[@]}"; do
  repo="$(repo_for "$app")"
  echo "==> $app: checking the latest release of $repo"

  api_url="$API/repos/$repo/releases/latest"
  response="$(curl -sSL --retry 3 --retry-delay 2 --connect-timeout 20 \
    "${api_headers[@]}" -w '\n%{http_code}' "$api_url")" || {
    echo "error: could not reach $api_url" >&2
    exit 1
  }
  status="${response##*$'\n'}"
  release="${response%$'\n'*}"

  if [[ "$status" != "200" ]]; then
    echo "error: $api_url returned HTTP $status" >&2
    if [[ "$status" == "403" || "$status" == "429" ]]; then
      echo "       (API rate limit; set GH_TOKEN, or check that the token is valid)" >&2
    fi
    exit 1
  fi

  tag="$(jq -er '.tag_name' <<<"$release")" || {
    echo "error: $repo does not have a latest release" >&2
    exit 1
  }
  released="$(jq -r '.published_at // ""' <<<"$release")"
  release_url="$(jq -r '.html_url // ""' <<<"$release")"

  if [[ "$app" == "vibeoffice" ]]; then
    tarball="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
    jq -n --arg app "$app" --arg version "$tag" --arg released "$released" \
      --arg release_url "$release_url" --arg tarball "$tarball" \
      '{key: $app,
        value: {version: $version, released: $released,
                release_url: $release_url, tarball: $tarball, subdir: "public"}}' \
      >> "$WORK/apps.jsonl"
  else
    web_zip="$(jq -r --arg prefix "${app}-web-" '
      first(.assets[]?
            | select(.name | startswith($prefix) and endswith(".zip"))
            | .browser_download_url) // empty
    ' <<<"$release")"

    if [[ -z "$web_zip" ]]; then
      echo "error: $repo@$tag has no ${app}-web-*.zip asset" >&2
      exit 1
    fi

    jq -n --arg app "$app" --arg version "$tag" --arg released "$released" \
      --arg release_url "$release_url" --arg web_zip "$web_zip" \
      '{key: $app,
        value: {version: $version, released: $released,
                release_url: $release_url, web_zip: $web_zip}}' \
      >> "$WORK/apps.jsonl"
  fi

  echo "    $tag ($released)"
done

jq -s --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  from_entries
  | {checked_at: $checked_at, apps: .}
' < "$WORK/apps.jsonl" > "$WORK/versions.json"

changed=true
if [[ -f "$VERSIONS" ]] &&
  jq -e --slurpfile new "$WORK/versions.json" '.apps == $new[0].apps' "$VERSIONS" >/dev/null 2>&1; then
  changed=false
fi

if [[ "$changed" == true ]]; then
  cp -- "$WORK/versions.json" "$VERSIONS"
  echo
  echo "versions.json updated:"
  jq -r '.apps | to_entries[] | "  \(.key): \(.value.version)"' "$VERSIONS"
else
  echo
  echo "No version changes."
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=$changed" >> "$GITHUB_OUTPUT"
fi
