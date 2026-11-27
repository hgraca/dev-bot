---
date: 2026-11-27
keywords: ["php", "composer", "plugin", "post-install"]
aliases: ["hollow version bump", "scripts not synced"]
---

## A failing post-install script leaves a composer plugin's files unsynced

A Composer plugin that copies files into the consumer repo (a `scripts/` directory, workflows) does it in a post-install script. If *any* script in the chain fails first — `artisan package:discover` failing on missing generated classes is the usual cause — the sync never runs, yet `composer require` has already written the new version into `composer.json`. The result is a **hollow bump**: the version says the new release, the synced files are the old ones, and nothing errors. Always diff one synced file against the tag (`git show <tag>:src/… | diff - scripts/…`) after bumping, and re-run `composer install` once the failure's cause is fixed so the plugin actually syncs.
