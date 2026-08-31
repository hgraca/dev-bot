---
date: 2026-06-29
keywords: ["php", "composer", "source-fallback", "codeload", "github"]
trigger-on: ["composer-install-ci", "codeload-http-400", "composer-dist-failure"]
---

## Composer source-fallback config for GitHub codeload HTTP errors

When CI `composer install --prefer-dist` fails with HTTP/2 400 from `codeload.github.com`, the fix is to add `"source-fallback": true` to `composer.json` under `config`. This allows Composer to automatically fall back to git clone when dist zip downloads fail. Setting `preferred-install` to `"auto"` does NOT enable source fallback — that config only picks between dist/source per package, and once dist is selected, fallback remains disabled. The `source-fallback` key is the dedicated toggle for this behavior.
