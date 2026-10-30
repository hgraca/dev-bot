---
date: 2026-10-30
keywords: ["php", "composer", "plugin", "no-scripts", "no-plugins"]
aliases: ["composer update plugin still runs", "skip composer plugins"]
trigger-on: ["composer-plugin-event-listener"]
---

## `--no-scripts` does not stop Composer plugin listeners; `--no-plugins` does

`--no-scripts` only sets `EventDispatcher::runScripts = false`, which suppresses the scripts declared in `composer.json`; `EventDispatcher::getListeners()` still merges the listeners a plugin registered in `activate()`, so a plugin's `post-install-cmd`/`post-update-cmd` handler runs anyway. Only `--no-plugins` keeps the plugin from being loaded (`Factory::create` / `Installer::disablePlugins()`), which is what a lock-only bump needs: `composer update <pkg> --no-install --no-plugins` rewrites `composer.lock` alone, while `--no-install` on its own re-runs the plugin already in `vendor/` — with a stale package under it, that plugin can overwrite generated files with older content. Verify the behaviour in the vendored `composer/composer` `EventDispatcher` when a flag's effect matters.
