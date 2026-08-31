---
date: 2026-06-24
keywords: ["laravel", "wayfinder", "vite", "php"]
trigger-on: ["wayfinder-vite-plugin", "vite-dev-php-required", "wayfinder-generate"]
---

## Wayfinder Vite plugin requires PHP at dev server startup

The `@laravel/vite-plugin-wayfinder` runs `php artisan wayfinder:generate --with-form` during Vite's `buildStart` hook. If `php` is not in the Vite process's PATH (e.g., running Vite on host without PHP, or in a Node-only container), Vite fails to start. Fix: run Vite and PHP in the same container (e.g., a dev Docker image with both Node/pnpm and PHP), or ensure a working `php` wrapper script is on PATH before starting Vite.
