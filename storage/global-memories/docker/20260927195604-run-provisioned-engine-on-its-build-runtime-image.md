---
date: 2026-09-27
keywords: ["docker", "engine", "runtime", "image", "composer"]
trigger-on: ["container-image-for-provisioned-tool", "scratch-engine-image-mismatch"]
---

## Run a provisioned engine on an image matching *its* build runtime, not the target project's

An engine installed into a scratch dir by a build image inherits that image's runtime: a Composer install performed with `composer:2` (PHP 8.5) writes a `vendor/` whose `platform_check.php` requires PHP >= 8.5. Running it inside an image chosen from the *analysed project's* declared runtime (`php:7.0-cli` for a `"php": ">=7.0"` project) then fatals on the platform check, and the feature silently yields nothing. Record the engine's build runtime at provision time (e.g. write the PHP version to `storage/.../.php-version`) and resolve the container image from that — falling back to the project's own image only when the engine came from the project. Report the chosen image in `doctor` so a mismatch is visible.
