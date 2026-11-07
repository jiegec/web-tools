#!/usr/bin/env bash
#
# Assemble the web-tools site from the versions pinned in versions.json:
#   <out>/index.html, <out>/favicon.svg, <out>/versions.json,
#   and <out>/<app>/ with that release's web build: a WebAssembly zip, or the
#   static source tree of an app that ships plain HTML/JS (VibeOffice).
#
# versions.json is maintained by scripts/check-versions.sh.
#
# Usage:
#   scripts/build-site.sh [output-dir]     (default: ./dist)
#
# Requires: curl, jq, tar, unzip.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/dist"}"
APPS=(
  wordcraft photocraft deckcraft gridcraft
  pdfcraft lightcraft filmcraft cadcraft soundcraft materialcraft
  designcraft texturecraft figcraft vectorcraft effectcraft
  vibeoffice
)
VERSIONS="$ROOT/versions.json"

for tool in curl jq tar unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' is required but was not found in PATH" >&2
    exit 1
  fi
done

if [[ ! -f "$VERSIONS" ]]; then
  echo "error: $VERSIONS is missing; run scripts/check-versions.sh first" >&2
  exit 1
fi

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

for app in "${APPS[@]}"; do
  tag="$(jq -er --arg app "$app" '.apps[$app].version' "$VERSIONS")" || {
    echo "error: versions.json has no version for $app" >&2
    exit 1
  }
  web_zip="$(jq -r --arg app "$app" '.apps[$app].web_zip // empty' "$VERSIONS")"
  tarball="$(jq -r --arg app "$app" '.apps[$app].tarball // empty' "$VERSIONS")"

  extract="$WORK/extract-$app"
  mkdir -p -- "$extract"

  if [[ -n "$web_zip" ]]; then
    archive="$WORK/$app.zip"
    echo "==> $app: downloading $tag"
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
      -o "$archive" "$web_zip"; then
      echo "error: could not download $web_zip" >&2
      exit 1
    fi

    unzip -q "$archive" -d "$extract"

    # The zip holds a single top-level directory (e.g. wordcraft-web-0.16.0/);
    # accept a zip with index.html at its root too.
    source_root="$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    if [[ -z "$source_root" || ! -f "$source_root/index.html" ]]; then
      source_root="$extract"
    fi
    if [[ ! -f "$source_root/index.html" ]]; then
      echo "error: $app@$tag web zip does not contain an index.html" >&2
      exit 1
    fi
  elif [[ -n "$tarball" ]]; then
    subdir="$(jq -r --arg app "$app" '.apps[$app].subdir // empty' "$VERSIONS")"
    if [[ -z "$subdir" ]]; then
      echo "error: versions.json has no subdir for $app" >&2
      exit 1
    fi

    archive="$WORK/$app.tar.gz"
    echo "==> $app: downloading $tag (source)"
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
      -o "$archive" "$tarball"; then
      echo "error: could not download $tarball" >&2
      exit 1
    fi

    tar -xzf "$archive" -C "$extract" --strip-components=1
    source_root="$extract/$subdir"
    if [[ ! -f "$source_root/index.html" ]]; then
      echo "error: $app@$tag has no $subdir/index.html" >&2
      exit 1
    fi
  else
    echo "error: versions.json has no web_zip or tarball for $app" >&2
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

  echo "==> $app: $tag"
done

cp -- "$ROOT/index.html" "$OUT/index.html"
cp -- "$ROOT/favicon.svg" "$OUT/favicon.svg"
touch -- "$OUT/.nojekyll"

jq --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '. + {generated_at: $generated_at}' "$VERSIONS" > "$OUT/versions.json"

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
