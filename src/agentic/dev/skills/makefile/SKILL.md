---
name: makefile
description: "Makefile lifecycle commands: running CLI commands inside containers, starting and stopping the development environment. Use this skill whenever running application commands, starting the dev environment, or extending the build lifecycle — e.g. 'run the tests', 'start the app', 'add a make target'."
---

# Makefile

## When to Apply

- Running CLI commands in application
- Starting or stopping development environment
- Extending build lifecycle with new commands

## Rules

Never bypass Makefile. Extend it if lifecycle changes required.

- Run all CLI commands inside `app` container via `make run CMD="..."`

## Lifecycle commands

- `make install`: Full installation (first-time setup or reinstall)
- `make up`: Boot services (no installation)
- `make run CMD='...'`: Run command inside application container
- `make down`: Stop development environment
- `make update`: Upgrade all tools + install any missing

## See also

- `make-tests` skill
