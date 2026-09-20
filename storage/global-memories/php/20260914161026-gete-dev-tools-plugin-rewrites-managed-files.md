---
date: 2026-09-14
keywords: ["php", "composer", "dev-tools", "github-actions", "managed-files"]
trigger-on: ["gete-dev-tools-managed-files", "dev_tools-workflows-regenerated", "actions-checkout-version-downgrade"]
---

## The get-e/dev-tools composer plugin rewrites its managed files on every composer run

In GET-E projects the `get-e/dev-tools` composer plugin prints `🔄 DevTools updated!` and rewrites the files it manages (root `Makefile`, `.github/workflows/dev_tools-*.yml`, composer scripts) on every `composer install`/`update`/`require`. Their content follows the **installed** dev-tools version, not what is committed — so an ordinary `composer update` can yield an apparently unrelated diff that *downgrades* pinned GitHub Actions (observed: `actions/checkout@v7` → `@v4`, `dependabot/fetch-metadata@v3.1.0` → `@v2.5.0`, `slackapi/slack-github-action@v4.0.0` → `@v2.0.0`) when the local dev-tools is older than whatever produced the committed files. Never hand-edit these files, and never commit the downgrade as if it were the change: bump `get-e/dev-tools` in `composer.json` to a version shipping the newer templates (`composer require --dev get-e/dev-tools:^X.Y.Z`) and re-run composer — that restores the newer action refs and surfaces the genuine upstream changes (e.g. `COMPOSER_AUTH` `github-oauth` → `http-basic`, `needs`/quoting normalisation).
