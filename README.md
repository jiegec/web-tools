# web-tools

A small static site that republishes the latest browser (WebAssembly) builds of the Craft apps:

| App | Path | Upstream |
| --- | --- | --- |
| WordCraft | `/wordcraft/` | [storytold/wordcraft](https://github.com/storytold/wordcraft) |
| PhotoCraft | `/photocraft/` | [storytold/photocraft](https://github.com/storytold/photocraft) |
| DeckCraft | `/deckcraft/` | [storytold/deckcraft](https://github.com/storytold/deckcraft) |
| GridCraft | `/gridcraft/` | [storytold/gridcraft](https://github.com/storytold/gridcraft) |

`index.html` is the landing page linking to each app. A GitHub Actions workflow rebuilds the
site **every Monday at 03:23 UTC** (11:23 Asia/Shanghai), taking the newest `*-web-*.zip`
asset from each project's latest GitHub release, so the site follows upstream releases without
any commits here.

## One-time setup

1. Push this repository to GitHub.
2. Open **Settings → Pages → Build and deployment**, and set **Source** to **GitHub Actions**.
3. Optionally run the workflow once from the **Actions** tab.

The site is published at `https://<owner>.github.io/web-tools/`. Because every app bundle uses
relative URLs and works under any prefix, the apps end up at
`https://<owner>.github.io/web-tools/wordcraft/` and so on.

The workflow also runs on pushes that touch `index.html`, `favicon.svg`, `scripts/`, or the
workflow itself, and it can be started by hand with **Run workflow**.

## How it works

- [`scripts/build-site.sh`](scripts/build-site.sh) resolves each app's latest release through
  the GitHub API, downloads its `*-web-*.zip`, unpacks it into `dist/<app>/`, and writes
  `dist/versions.json` with the version and release date of each app.
- [`index.html`](index.html) is copied to the site root as-is; its small script fetches
  `versions.json` and fills in the version badges (an offline preview simply keeps `latest`).
- [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) uploads `dist/` as a Pages
  artifact and deploys it with `actions/deploy-pages`.

The build also works around an upstream PhotoCraft packaging bug: releases 0.17.0–0.21.0 ship
the wasm-bindgen `snippets/` folder at the site root while `app/photocraft-web.js` imports it
relative to `app/`, so the app never starts. The script copies `snippets/` into `app/` until a
release contains the fix ([storytold/photocraft#10017](https://github.com/storytold/photocraft/issues/10017)).

The `.nojekyll` file is added to the output so the artifact stays correct even if the site is
ever served by the legacy Jekyll build.

## Preview locally

```sh
./scripts/build-site.sh
python3 -m http.server 8000 --directory dist
# then open http://localhost:8000/
```

Requires `curl`, `jq` and `unzip`. A build downloads roughly 60 MB of release assets and makes
four GitHub API requests (the workflow authenticates with its `GITHUB_TOKEN`; locally, set
`GH_TOKEN` if you hit the anonymous rate limit). `SOURCE_ORG=your-org` overrides the upstream
owner.

## Adjusting the site

- **Apps or order:** edit the `APPS` array in `scripts/build-site.sh` and the matching cards in
  `index.html`.
- **Schedule:** edit the `cron:` line in the workflow. GitHub's cron is UTC.
- **Landing page:** it is plain HTML/CSS with no build step; edit `index.html` and push.

## Notes

- GitHub Pages does not let you set custom cache headers, so the `_headers`/`.htaccess` files
  included in the release zips are inert here. Hashed asset names plus GitHub Pages' ETags
  still give reasonable caching.
- The site is at most one week behind upstream; run the workflow manually to pick up a release
  immediately.
- GitHub disables scheduled workflows after 60 days without repository activity. If the site
  stops updating, re-enable the workflow from the Actions tab (or push any commit).
- The first deployment needs Pages already configured with the GitHub Actions source;
  otherwise the deploy job fails with a "Get Pages site failed" error.
