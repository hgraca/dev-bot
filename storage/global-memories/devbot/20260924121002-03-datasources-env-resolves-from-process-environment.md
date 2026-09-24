---
date: 2026-09-24
keywords: ["devbot", "datasources", "environment", "reproducibility"]
trigger-on: ["devbot-datasources-config"]
---

## dev-bot datasources resolve `${VAR}` from the process environment, not specifically `.env`

`render.sh` sources `DEV_BOT_ROOT/.env` (`set -a; source .env; set +a`) _and_ inherits its caller's environment; `up.sh` does the same before `docker compose up`, and the rendered compose passes each name through as `environment: ["VAR"]`, whose value comes from the compose process's environment. So the value may come from `.env`, from an `export` in the shell that ran `devbot up`, or from anywhere else in that chain — `.env` is the recommended home, not the mechanism.

Consequence: the published config is a function of who ran the boot. `available_catalogue.py` requires the ref to resolve in the render process's environment and otherwise drops that source as `required env not set`, so a boot from a shell without the export silently publishes a config _without_ the datasource and the tool disappears — the same repo yields different tool sets on different machines. Put secrets in `.env` when the boot must be deterministic and survive a reboot.
