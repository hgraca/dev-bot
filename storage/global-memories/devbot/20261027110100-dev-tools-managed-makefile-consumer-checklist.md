---
date: 2026-10-27
keywords: ["devbot", "dev-tools", "makefile", "compose", "php"]
trigger-on: ["dev-tools-make-true", "adopt-managed-makefile"]
---

## Adopting dev-tools' managed Makefile: the consumer checklist

Turning `make: true` on in `extra."GET-E/dev-tools"` replaces the repo's Makefile and `scripts/` with the generated ones, and the generated `up` chain assumes more than the plugin copies. Before flipping it, a PHP consumer needs:

- `.docker/compose.dev.yml` with a service literally named `app` (the Makefile runs `docker compose … run --rm app` and `docker exec … ${PROJECT_NAME}-app-1`) and `name: ${PROJECT_NAME:-<project>}` so worktrees get their own containers;
- `.env.dist` (the Makefile's `init` copies it to `.env`), plus `.docker/{php,xdebug}.overrides.ini.dist` for `init-php`;
- `vendor/get-e/dev-tools` present before `make up`, because `up` composes `vendor/get-e/dev-tools/src/Docker/compose.shared.yml` and waits for `shared-redis-1`;
- a `Makefile.proj.mk`, which is where every project-specific target belongs. The shipped template assumes a `db:create` artisan command and MongoDB; an app with neither must replace `migrate`/`db-*`/`.unit`'s DB bootstrap with plain `php artisan migrate` / `phpunit`. It also declares `unit-ci`-style CI targets only as `ci-unit`, so a repo whose workflows call `make unit-ci` must define those names itself;
- configs for `rector`, `phplint`, `phparkitect` and `composer-dependency-analyser` — the generated Makefile exposes `.rect`, `.lint`, `.arch`, `.dependency-analyser`, and without the repo's config they fail. Stub them in `Makefile.proj.mk` with an explicit message rather than leaving `No rule to make target`.

The dev image must also carry composer, make, pcov and xdebug: the generated targets call `make` inside the container and the coverage target expects pcov.
