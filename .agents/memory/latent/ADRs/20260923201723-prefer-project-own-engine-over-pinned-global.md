---
date: 2026-09-23
keywords: ["refactor", "rector", "engine", "tooling"]
---

## Prefer the project's own engine version over a globally pinned one

For the `refactor` module's PHP engine, run the project's own `vendor/bin/rector` rather than a globally pinned install, using a pinned scoped Composer install only as the fallback for projects that have no Rector. Rationale: Rector's PHPStan-based reflection needs the project's `vendor/autoload.php`, and its **version** changes rule behaviour — `core` locks Rector 2.4.3 while the current release is 2.6.x, so a global pin would rename using a different engine than the project's own CI. The same reasoning drove preferring the project's own container image over a generic `php` one, since a generic image lacks the extensions that `vendor/composer/platform_check.php` asserts at autoload time. Three related decisions follow from it: there is deliberately **no phar** (upstream abandoned that distribution because it broke on absolute paths and Docker mounts — exactly a container-mount setup); the project's own `rector.php` is **never applied**, because its Laravel/PHPUnit/Carbon/PHP-84 rule sets would rewrite unrelated code, so the tool renders its own single-rule config and pins it with `--only`; and the accepted cost is a provisioning step for the no-Rector case rather than a self-contained tool.
