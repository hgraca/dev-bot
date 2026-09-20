---
date: 2026-09-02
keywords: ["php", "composer", "class_alias", "autoload", "queue"]
trigger-on: ["composer-class-alias-files-autoload"]
---

## A `composer_class_aliases.php` file must be registered in `autoload.files` to run

Adding a root-level `composer_class_aliases.php` containing `class_alias('New\Fqcn', 'Old\Fqcn')` (e.g. to rehydrate message-queue payloads serialized with a pre-move namespace) does nothing unless Composer executes the file: PSR-4 alone never loads it, so the alias silently never registers and old-FQCN payloads still fail to unserialize. Register it under `composer.json` → `autoload` → `"files": ["composer_class_aliases.php"]` and run `composer dump-autoload`. Verify with `php -r 'require "vendor/autoload.php"; var_dump(class_exists("Old\Fqcn"));'`.
