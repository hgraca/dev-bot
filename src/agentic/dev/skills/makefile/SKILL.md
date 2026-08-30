---
name: devbot:makefile
description: "Make-based project lifecycle: running commands inside the app container, and creating the DevTools makefiles structure (main Makefile + per-language .mk files). Use this skill whenever running project commands via make, starting/stopping the dev environment, or setting up/extending a project's makefiles."
---

# Makefile

## When to Apply

- Running CLI commands inside the application container.
- Starting or stopping the development environment.
- Creating the makefiles structure for a new project, or extending an existing one.

## Rules

- Never bypass the Makefile — extend it when the lifecycle changes.
- Run all CLI commands inside the `app` container, never on the host (avoids permission issues and keeps commands in the project environment).

## Makefiles structure

The canonical makefiles live in `/home/herberto/Development/Get-e/dev-tools/src/Make/`. The same files are bundled as reference templates in this skill's `assets/` directory.

| File                     | Role                                                                     |
| ------------------------ | ------------------------------------------------------------------------ |
| `Makefile`               | Main entry point — centrally managed by DevTools, shared across projects |
| `Makefile.php.mk`        | PHP-specific targets (composer, artisan, phpunit, static analysis)       |
| `Makefile.java.mk`       | Java-specific targets                                                    |
| `Makefile.proj.mk`       | Project-specific targets — committed, `include`d by the main Makefile    |
| `Makefile.local.mk`      | Personal, git-ignored targets                                            |
| `Makefile.vars.local.mk` | Personal, git-ignored variable overrides                                 |

The main `Makefile` `include`s `Makefile.proj.mk`, `Makefile.local.mk`, and `Makefile.vars.local.mk` when present.

## Creating the structure for a new project

1. Copy `assets/Makefile` into the project root as `Makefile`.
2. Copy the language-specific `assets/Makefile.<lang>.mk` matching the project's stack (e.g. `Makefile.php.mk` for PHP, `Makefile.java.mk` for Java).
3. Add project-specific targets to `Makefile.proj.mk` (committed). Do **not** edit the main `Makefile` — it is centrally managed and overwritten on update.
4. Personal workflow targets go in `Makefile.local.mk`; variable overrides in `Makefile.vars.local.mk` (both git-ignored).

## Key conventions

- `.SILENT` and `MAKEFLAGS += --no-print-directory` mute make noise; `.DEFAULT_GOAL := help`.
- `help` scans `Makefile`, `Makefile.proj.mk`, and `Makefile.local.mk` for `##` comments to build the command list — every public target should carry a `## description`.
- `.docker-wrap-%` pattern rule runs the dotted target inside the `app` container when not already inside Docker — the mechanism behind `test`, `static`, `unit`, `ut`, `cov`, `fix`, `lint`, `cs`, `stan`, `arch`, etc.
- Namespace-prefix aggregate targets — `init`, `install`, `db`, `migrate`, `seed`, `generate`, `workers` — run every `init-*`, `install-*`, `db-*`, … target found across all included files.
- Docker helpers: `RUN` (container not yet booted), `EXEC` (container booted), `EXEC_ROOT` (as root), `SH`.
- `UID`/`GID` map the host user into the container to avoid permission mismatches.

## Lifecycle commands

- `make help` — list all available commands
- `make up` / `make down` — start / stop the dev environment
- `make app` — open a shell in the running app container
- `make run CMD='...'` — run a command inside the app container
- `make init` / `make install` / `make update` — initialize / install / update dependencies
- `make test` / `make static` / `make unit` / `make ut` / `make cov` — run the test suite
- `make lint` / `make cs` / `make stan` / `make rect` / `make arch` — run static analysis / fixers

## Assets

Reference makefiles (templates) are bundled in this skill:

- `assets/Makefile`
- `assets/Makefile.php.mk`
- `assets/Makefile.java.mk`

## See also

- `devbot:make-tests` skill
