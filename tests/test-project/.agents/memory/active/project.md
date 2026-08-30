---
tags: [bootstrap, project]
description: What kata-pokeapi_parser_refactoring is, how repo laid out, key conventions and rough edges
---

## What this project is

PHP 8.4 CLI kata (`kata-pokeapi_parser_refactoring`) to practice refactoring, tests and polymorphism. Reads Pokemon names from argv, fetches base_experience + species + growth-rate levels from https://pokeapi.co/, computes each Pokemon's current level, prints `name experience species level` (spec in README.md). Uses GET-E's private `get-e/message-bus` library (dev-main) for CQRS query dispatch. All code under namespace `Gete\PokeParser\` in `src/`.

## Repository layout

| Path                          | Contents                                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bin/run.php`                 | CLI entry point: wires HTTP providers + inline anonymous HandlerResolver → QueryDispatcher → PokemonLevelService, prints results                                          |
| `src/Domain/`                 | Pure value objects: Pokemon, PokemonName, Species, Level, ExperiencePoints, GrowthRateLevel, GrowthRateLevelTable, GrowthRateReference                                    |
| `src/Application/`            | CQRS: queries (FetchPokemonData, FetchGrowthRateLevels), handlers, port interfaces (PokemonDataProvider, GrowthRateLevelProvider), PokemonLevelService, PokemonDataResult |
| `src/Infrastructure/PokeApi/` | HTTP adapters implementing Application ports: HttpPokemonDataProvider, HttpGrowthRateLevelProvider                                                                        |
| `tests/`                      | PHPUnit 9.5 suite mirroring src layers + Integration/PokeApi/RunScriptTest (execs bin/run.php end-to-end)                                                                 |
| `vendor/`                     | Composer deps incl. get-e/message-bus (gitignored)                                                                                                                        |
| `composer`                    | Committed composer.phar (3 MB) — run as `./composer`                                                                                                                      |
| `.agents/`                    | DevBot memory vault, skills, tools; memory gitignored (agent working state)                                                                                               |
| `.opencode/`                  | Opencode config; agents/commands/skills/tools symlinked into `.agents/`                                                                                                   |
| `graphify-out/`               | Knowledge-graph output (gitignored)                                                                                                                                       |
| `no-vcs/`                     | Never read or modify (see `.agents/memory/active/ignore.md`)                                                                                                              |
| `build/`                      | Test-coverage output (gitignored)                                                                                                                                         |

## Architecture

DDD-lite hexagonal with CQRS: `src/Domain/` (immutable value objects) ← `src/Application/` (query/handler use cases + port interfaces) ← `src/Infrastructure/PokeApi/` (HTTP adapters). Dependencies point inward — Infrastructure implements Application ports; Application references Domain types only.

- Entry point: `bin/run.php` — inline anonymous HandlerResolver maps handler FQCN → handler instance; QueryDispatcher (message-bus `GetE\MessageBus\Adapter\Dummy\QueryDispatcher`) routes `FetchPokemonData` / `FetchGrowthRateLevels` queries.
- Data flow: PokemonLevelService dispatches `FetchPokemonData` → PokemonDataResult → `FetchGrowthRateLevels` → GrowthRateLevelTable; `levelFor(experience)` picks the level; output formatted in bin/run.php.
- External service: https://pokeapi.co/api/v2/ — HTTP via injected `$httpGetter` closure (fopen stream, JSON_THROW_ON_ERROR).
- Cross-cutting: no auth, no logging, no framework — plain PHP + message-bus only.

## Lifecycle & workflows

No Makefile. Composer scripts are the preferred command channel (composer.json):

- `./composer install` — install deps (committed phar; lock file is gitignored)
- `./composer tests` — PHPUnit
- `./composer check-cs` / `fix-cs` — EasyCodingStandard
- `./composer phpstan` — PHPStan, level max
- `./composer dev` — fix-cs + phpstan + tests
- `./composer app` — run CLI with the 4 sample pokemon
- `./bin/run.php ivysaur ...` — direct run

## Runtime & deployment

Plain PHP 8.4 CLI. No Dockerfile, no compose file, no deploy config in repo (README suggests an ad-hoc `docker run php:8.4-cli` container). No CI (no `.github/workflows`, no `.gitlab-ci.yml`). Nothing auto-deploys.

## Critical conventions

- `declare(strict_types=1)` in every file; `final readonly` classes with constructor promotion and readonly props (see php-rules).
- Queries implement `GetE\MessageBus\Port\QueryBus\Query`; handlers implement `QueryHandler` with `__invoke`; `/** @implements Query<Result> */` PHPDoc (see message-bus).
- Ports live in Application, adapters in Infrastructure — never import Infrastructure from Application.
- Tests: PHPUnit 9.5, `/** @test */` docblocks + data providers, `@covers` on the class, PSR-4 `Gete\PokeParser\Test\`.
- PHPStan level max must pass; ECS enforces style.
- Memory vault `.agents/memory/` is gitignored (via `.git/info/exclude`) — never `git add` memory files.
- `no-vcs/` never read/modified. `.agents/` + `.opencode/` are agent config, gitignored.
- Commit style is Conventional Commits (types feat/fix/chore/docs).

## Rough edges

- No CI at all — nothing runs checks on merge.
- `composer.lock` is gitignored; deps are `dev-main` from private repos — installs not reproducible.
- `test.sh` deletes agent config files (`.opencode`, `.devbot.project.jsonc`, etc.) then re-runs `devbot init` — destructive helper, handle with care.
- Files owned by root (`vendor/`, `build/`, `composer.lock`, `.phpunit.result.cache`) — permission quirks from running inside container.
- README describes the challenge; repo already completed Tasks 1–9 — README not updated to reflect the final solution.
- Commit history has a stray `WIP` commit (427cacb) and non-conventional `Task N: ...` subjects mixed with Conventional Commits.

## When to read docs vs code

| Question                            | Go to                                |
| ----------------------------------- | ------------------------------------ |
| What the kata asks for / sample I/O | README.md                            |
| CQRS pattern / query-handler shape  | src/Application/ + message-bus skill |
| HTTP adapter behaviour              | src/Infrastructure/PokeApi/          |
| Domain rules (level calc, VOs)      | src/Domain/ + tests/Domain/          |
| CLI wiring                          | bin/run.php                          |
| Test conventions                    | tests/ + make-tests skill            |
