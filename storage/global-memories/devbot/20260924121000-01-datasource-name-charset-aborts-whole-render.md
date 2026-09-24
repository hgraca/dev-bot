---
date: 2026-09-24
keywords: ["devbot", "datasources", "mcp-toolbox", "naming"]
trigger-on: ["devbot-datasources-config", "mcp-toolbox-config"]
---

## A datasource name outside `[a-z0-9-]` aborts the entire render, not just that source

In dev-bot's datasources module a datasource name must match `^[a-z][a-z0-9-]*$` (`render_tools_yaml.py`, `NAME_RE`) — underscores are invalid, so `mongo-prod-audit_log` is rejected. The check lives in `validated_items()`, the single validation path shared by `available_catalogue.py` and `render_tools_yaml.py`, and it `_fail`s (exit 1) instead of skipping the source. `render.sh` runs the pipeline under `pipefail`, so one bad name aborts the whole render: nothing is published, and the gateway keeps serving the previous `conf/tools.yaml` — the symptom is a _missing tool_, with no message naming the name.

That asymmetry is the trap: an env-incomplete or unreachable source is dropped individually with an `INFO:` reason, but an invalid _name_ (or an unknown `type`, or an unsupported `read_only` key) takes every datasource's update down with it. Fix: hyphenate the name and keep it byte-identical in `.devbot.global.jsonc` (declaration) and `.devbot.project.jsonc` (opt-in list). Reproduce in milliseconds without docker: `read_jsonc.py .devbot.global.jsonc datasources | available_catalogue.py`.
