# web-tools

A small static site that republishes the browser (WebAssembly) builds of the Craft apps:

| App | Path | Upstream |
| --- | --- | --- |
| WordCraft | `/wordcraft/` | [storytold/wordcraft](https://github.com/storytold/wordcraft) |
| PhotoCraft | `/photocraft/` | [storytold/photocraft](https://github.com/storytold/photocraft) |
| DeckCraft | `/deckcraft/` | [storytold/deckcraft](https://github.com/storytold/deckcraft) |
| GridCraft | `/gridcraft/` | [storytold/gridcraft](https://github.com/storytold/gridcraft) |

The versions that get deployed are the ones recorded in [`versions.json`](versions.json). A
scheduled workflow checks the upstream releases every Monday, commits the updated versions when
something new appears, and triggers the Pages deployment from that commit. When nothing changed,
the check leaves both the repository and the site alone.

## One-time setup

1. Push this repository to GitHub.
2. Open **Settings → Pages → Build and deployment**, and set **Source** to **GitHub Actions**.
3. Optionally run **Check for new app releases** once from the **Actions** tab.

The site is published at `https://jia.je/web-tools/` with the custom domain configured for this
repository, or at `https://<owner>.github.io/web-tools/` for a fork without one. Every app bundle
uses relative URLs, so the apps end up at `/web-tools/wordcraft/` and so on.

## How a release reaches the site

1. **Check for new app releases** ([workflow](.github/workflows/check-versions.yml)) runs every
   Monday at 03:23 UTC (11:23 Asia/Shanghai), or on demand. It calls
   [`scripts/check-versions.sh`](scripts/check-versions.sh), which resolves each project's latest
   `*-web-*.zip` release through the GitHub API.
2. If a version differs from `versions.json`, the script rewrites the file with the new tag,
   release date, release URL and asset URL. The workflow commits it as
   `github-actions[bot]` and pushes to the current branch. That commit also counts as repository
   activity, which is what keeps GitHub from disabling the schedule after 60 quiet days.
3. A push made with `GITHUB_TOKEN` does not trigger other workflows, so the check workflow
   explicitly runs `gh workflow run deploy.yml` after pushing. The deployment therefore starts
   from the new commit.
4. **Deploy to GitHub Pages** ([workflow](.github/workflows/deploy.yml)) checks out that commit and
   runs [`scripts/build-site.sh`](scripts/build-site.sh). The script downloads the exact releases
   pinned in `versions.json`, unpacks each into `dist/<app>/`, copies the landing page, and writes
   `dist/versions.json` (the pinned versions plus a `generated_at` deployment timestamp).
5. The build is uploaded as a Pages artifact and deployed with `actions/deploy-pages`.

The deployment workflow also runs on pushes that touch `versions.json`, `index.html`,
`favicon.svg`, `scripts/build-site.sh`, or the workflow itself, and it can be run by hand from the
Actions tab to redeploy the current pins.

The build works around an upstream PhotoCraft packaging bug: releases 0.17.0–0.21.0 ship the
wasm-bindgen `snippets/` folder at the site root while `app/photocraft-web.js` imports it relative
to `app/`, so the app never starts. The script copies `snippets/` into `app/` until a release
contains the fix ([storytold/photocraft#10017](https://github.com/storytold/photocraft/issues/10017)).

The `.nojekyll` file is added to the output so the artifact stays correct even if the site is ever
served by the legacy Jekyll build.

## Preview locally

```sh
# Optional: refresh versions.json from the latest upstream releases.
GH_TOKEN="$(gh auth token)" ./scripts/check-versions.sh

./scripts/build-site.sh
python3 -m http.server 8000 --directory dist
# then open http://localhost:8000/
```

Requires `curl`, `jq` and `unzip`. A build downloads roughly 60 MB of release assets. The check
makes four GitHub API requests; the workflow authenticates with its `GITHUB_TOKEN`, while a local
run without `GH_TOKEN` uses the anonymous rate limit. `SOURCE_ORG=your-org` overrides the upstream
owner.

## Adjusting the site

- **Apps or order:** edit the `APPS` arrays in `scripts/check-versions.sh` and
  `scripts/build-site.sh`, and the matching cards in `index.html`.
- **Schedule:** edit the `cron:` line in the check workflow. GitHub's cron is UTC.
- **Deploy now:** run **Check for new app releases** to pick up upstream releases immediately, or
  **Deploy to GitHub Pages** to redeploy the versions already pinned.
- **Landing page:** it is plain HTML/CSS with no build step; edit `index.html` and push.

## Notes

- GitHub Pages does not let you set custom cache headers, so the `_headers`/`.htaccess` files
  included in the release zips are inert here. Hashed asset names plus GitHub Pages' ETags still
  give reasonable caching.
- The site is at most one week behind upstream. Running the check workflow manually deploys a new
  release immediately.
- A commit is made only when a version changes. If upstream projects go 60 days without a release,
  GitHub can still disable the scheduled workflow; re-enable it from the Actions tab (or run the
  check manually) when that happens.
- The first deployment needs Pages already configured with the GitHub Actions source; otherwise the
  deploy job fails with a "Get Pages site failed" error.
