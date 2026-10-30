---
date: 2026-10-27
keywords: ["php", "composer", "composer update", "private vcs package", "composer.lock"]
trigger-on: ["composer-add-private-package", "composer-update-lock"]
---

## Adding a private VCS plugin: `composer update <pkg> -W` rewrites prod packages

`composer update <pkg> --with-all-dependencies` is the only way to satisfy a new package that forces a downgrade (e.g. `phparkitect ^1.7` needs `webmozart/assert ^1.9` while the lock carries 2.x), but `-W` also drags unrelated production packages forward — observed phpdotenv 5.7→5.8 plus guzzle/carbon/semver patch bumps. Prefer naming the forced package explicitly (`composer update <pkg> <forced-dep>`), which resolves the downgrade and adds only the newcomer's tree. Two environment traps: `composer update --lock` needs `git` in the image (a slim `php:*-cli` has none, and the failure prints the command usage instead of a clear error), and a full install of a Nova-licensed app returns HTTP 403 without Nova credentials — mount the host's `~/.config/composer` as `COMPOSER_HOME` (plus `SSH_AUTH_SOCK` for `git@github.com:` VCS repositories) rather than copying secrets.
