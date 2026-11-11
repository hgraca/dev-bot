---
date: 2026-11-11
keywords: ["composer", "dev-tools", "prefer-dist", "private-repo", "no-install"]
---

# Bumping a private VCS package (get-e/dev-tools) in a downstream project

## The command

Run `composer require --dev "get-e/dev-tools:^X.Y.Z" -W` inside the project's app container.

- A plain `composer require` (no `--dev`) moves the package from `require-dev` to `require`, and
  `composer-dependency-analyser` then fails with `Found 1 unused dependency: get-e/dev-tools`.
- `-W` (`--with-all-dependencies`) is required when the project's lock pins a transitive dependency
  that the new version constrains; without it composer refuses and tells you to use `-W`.
- When the image lacks `ext-zip` (no libzip), add `--ignore-platform-req=ext-zip` so composer can
  write the lock.

## CI: `--prefer-dist` cannot download private repos

Regenerating the lock adds GitHub zipball `dist` URLs for `get-e/*` and `phparkitect/*`. A CI job
running `composer install --prefer-dist` without a GitHub token gets HTTP 404 on those zipballs (the
composer cache masks it until the lock hash changes). The repos' SSH deploy keys are already set up,
so install the private packages from source and drop `--prefer-dist` (it overrides
`preferred-install`):

```yaml
run: |
  composer config preferred-install.'get-e/*' source
  composer config preferred-install.'phparkitect/*' source
  composer install --no-ansi --no-progress --no-interaction
```

## Private registries (Nova) return 403 on install

`laravel/nova` comes from a paid registry; a container without its credentials gets HTTP 403 on the
dist zip. If only the lock needs updating, run with `--no-install` (no download, no auth).

## Post-update scripts need vendor/

`composer update`/`require` runs `post-update-cmd` (`@php artisan vendor:publish`). In a fresh
checkout with no `vendor/`, that fails with "Failed opening required vendor/autoload.php" and reverts
the lock. Add `--no-scripts` when the goal is only to write the lock; CI installs with scripts.

## A real dependency conflict

`roave/security-advisories` (pulled by dev-tools) conflicts with a vulnerable
`symfony/html-sanitizer`. Update the guarded package to a patched release first
(`composer update symfony/html-sanitizer --with-dependencies --no-install --no-scripts`), then bump
dev-tools. A locked `laravel/nova` that keeps html-sanitizer on the vulnerable line is what blocks
`-W`.
