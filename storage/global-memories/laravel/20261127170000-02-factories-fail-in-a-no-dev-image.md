---
date: 2026-11-27
keywords: ["laravel", "factory", "faker", "no-dev", "docker"]
aliases: ["Call to undefined function fake", "seed command dies on staging", "dev dependencies missing in the image"]
trigger-on: ["laravel-seed-command", "model-factory", "dockerfile-production-stage"]
---

## A production image built with `composer install --no-dev` has no faker, so model factories cannot run there

`fakerphp/faker` is a `require-dev` package, and every Eloquent factory calls `fake()`. A console command or seeder that creates rows through `Model::factory()` therefore works perfectly in the test suite and dies on the box with `Call to undefined function Database\Factories\fake()` — the suite runs with dev dependencies installed, so nothing in CI sees it.

Two habits prevent the class. Write operational commands with explicit `Model::query()->create([...])` rows rather than factories: a seeded row is data, not a fixture, and fixed names make a re-run idempotent in a way faker's randomness does not. And add a CI job that installs `--no-dev` against a real database and executes the command — that is the only place the difference is observable. A cheap proxy is `[ -d vendor/fakerphp ] && fail`, which catches the day it returns.
