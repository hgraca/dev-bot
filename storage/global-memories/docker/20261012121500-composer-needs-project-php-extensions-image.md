---
date: 2026-10-12
keywords: ["docker", "composer", "php-extensions", "mongodb"]
trigger-on: ["composer-in-docker", "composer-platform-req-missing"]
---

## A bare `composer:2` image cannot resolve a project needing PHP extensions — use the project's own dev image

Running `composer require` in the stock `composer:2` image fails for GET-E PHP projects: the image lacks `ext-mongodb`, `ext-opentelemetry` and `ext-rdkafka`, so resolution aborts with "requires ext-… -> it is missing from your system" and rolls `composer.json`/`composer.lock` back. Mounting `~/.config/composer` (auth + cache) is enough for **resolution** — composer uses the GitHub API/zipball, no SSH needed — but not for install of a project with real platform requirements. Fix: run composer in the project's **own** dev image, which already carries the extensions: `docker run --rm --user $(id -u):$(id -g) -e COMPOSER_HOME=/composer-home -v ~/.config/composer:/composer-home -v <repo>:/app -w /app --entrypoint composer <project-dev-image> require --dev <pkg> --no-interaction`. Both the `composer:2` and the project images already set the composer entrypoint. Mounting `~/.ssh` into a root container fails anyway — host-owned keys are "bad owner or permissions".
