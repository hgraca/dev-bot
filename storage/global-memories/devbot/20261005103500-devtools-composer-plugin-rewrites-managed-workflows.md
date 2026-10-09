---
date: 2026-10-05
keywords: ["devbot", "dev-tools", "composer", "workflow", "side-effect"]
aliases: ["composer post-update rewrites ci workflow", "devtools plugin managed files", "!.agents exclusion reverted"]
trigger-on: ["composer-require-vcs-dependency", "dev-tools-managed-files"]
---

## The dev-tools composer plugin rewrites its managed files on `composer require/update`

Running `composer require`/`composer update` in a GET-E project activates the DevTools composer plugin ("DevTools updated!"), which re-syncs the files it owns. On 2026-10-05 a `composer require get-e/message-bus:^0.17.19.0` in `core` rewrote `.github/workflows/dev_tools-deploy_php_nginx.yml`, deleting the `- '!.agents/**'` path exclusion that commit `38f27bddaf` had deliberately added — the dev-tools template does not carry it — and the rewrite lands during post-update scripts, about 20 s after `composer.lock` is written. Always inspect `git status`/`git diff` after a composer operation and stage only the intended manifests, restoring the plugin's churn with `git checkout -- <managed-file>`; the durable fix belongs upstream in `get-e/dev-tools` (add the exclusion to the workflow template), because the next composer run overwrites any client-repo local edit.
