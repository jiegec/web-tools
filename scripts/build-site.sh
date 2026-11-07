#!/usr/bin/env bash
#
# Assemble the web-tools site:
#   <out>/index.html, <out>/favicon.svg, <out>/versions.json,
#   and <out>/<app>/ with the latest web (WebAssembly) build of each Craft app.
#
# Usage:
#   scripts/build-site.sh [output-dir]     (default: ./dist)
#
# Environment:
#   GH_TOKEN     token for the GitHub API (optional; only needed when
#                unauthenticated requests are rate-limited)
#   SOURCE_ORG   GitHub owner of the apps (default: storytold)
#
# Requires: curl, jq, unzip.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/dist"}"
ORG="${SOURCE_ORG:-storytold}"
API="https://api.github.com"
APPS=(wordcraft photocraft deckcraft gridcraft)

for tool in curl jq unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' is required but was not found in PATH" >&2
    exit 1
  fi
done

mkdir -p -- "$OUT"
OUT="$(cd -- "$OUT" && pwd)"

# Never wipe the repository, the home directory or something above them.
if [[ "$OUT" == "/" || "$OUT" == "$HOME" || "$ROOT" == "$OUT" || "$ROOT" == "$OUT"/* ]]; then
  echo "error: refusing to build into $OUT" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

rm -rf -- "$OUT"
mkdir -p -- "$OUT"

api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
  -H "User-Agent: web-tools-pages"
)
if [[ -n "${GH_TOKEN:-}" ]]; then
  api_headers+=(-H "Authorization: Bearer $GH_TOKEN")
fi

: > "$WORK/releases.tsv"

for app in "${APPS[@]}"; do
  echo "==> $app: resolving the latest release"

  api_url="$API/repos/$ORG/$app/releases/latest"
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
    echo "error: $ORG/$app does not have a latest release" >&2
    exit 1
  }
  released="$(jq -r '.published_at // ""' <<<"$release")"

  asset_url="$(jq -r --arg prefix "${app}-web-" '
    first(.assets[]?
          | select(.name | startswith($prefix) and endswith(".zip"))
          | .browser_download_url) // empty
  ' <<<"$release")"

  if [[ -z "$asset_url" ]]; then
    echo "error: $ORG/$app@$tag has no ${app}-web-*.zip asset" >&2
    exit 1
  fi

  archive="$WORK/$app.zip"
  echo "==> $app: downloading $(basename -- "$asset_url")"
  if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
    -o "$archive" "$asset_url"; then
    echo "error: could not download $asset_url" >&2
    exit 1
  fi

  extract="$WORK/extract-$app"
  mkdir -p -- "$extract"
  unzip -q "$archive" -d "$extract"

  # The zip holds a single top-level directory (e.g. wordcraft-web-0.16.0/);
  # accept a zip with index.html at its root too.
  source_root="$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  if [[ -z "$source_root" || ! -f "$source_root/index.html" ]]; then
    source_root="$extract"
  fi
  if [[ ! -f "$source_root/index.html" ]]; then
    echo "error: $ORG/$app@$tag web zip does not contain an index.html" >&2
    exit 1
  fi

  mkdir -p -- "$OUT/$app"
  cp -a -- "$source_root"/. "$OUT/$app"/

  # PhotoCraft 0.17.0-0.21.0 ships the app's wasm-bindgen snippets at the site
  # root, but app/photocraft-web.js imports them relative to app/. Put a copy
  # where the module looks. Remove this once storytold/photocraft#10017 is
  # fixed (PR storytold/photocraft#10248).
  if [[ -d "$OUT/$app/app" && -d "$OUT/$app/snippets" && ! -e "$OUT/$app/app/snippets" ]]; then
    cp -a -- "$OUT/$app/snippets" "$OUT/$app/app/snippets"
  fi

  printf '%s\t%s\t%s\thttps://github.com/%s/%s/releases/tag/%s\n' \
    "$app" "$tag" "$released" "$ORG" "$app" "$tag" >> "$WORK/releases.tsv"

  echo "==> $app: $tag ($released)"
done

cp -- "$ROOT/index.html" "$OUT/index.html"
cp -- "$ROOT/favicon.svg" "$OUT/favicon.svg"
touch -- "$OUT/.nojekyll"

jq -Rn --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  [inputs
   | select(length > 0)
   | split("\t")
   | {key: .[0], value: {version: .[1], released: .[2], release_url: .[3]}}]
  | from_entries
  | {generated_at: $generated_at, apps: .}
' < "$WORK/releases.tsv" > "$OUT/versions.json"

for app in "${APPS[@]}"; do
  if [[ ! -f "$OUT/$app/index.html" ]]; then
    echo "error: $OUT/$app/index.html is missing after the build" >&2
    exit 1
  fi
done

echo
echo "Site written to $OUT"
for app in "${APPS[@]}"; do
  printf '  /%s/  %s\n' "$app" "$(jq -r --arg app "$app" '.apps[$app].version' "$OUT/versions.json")"
done
