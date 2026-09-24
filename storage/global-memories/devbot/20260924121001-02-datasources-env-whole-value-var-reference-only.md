---
date: 2026-09-24
keywords: ["devbot", "datasources", "environment", "secrets"]
trigger-on: ["devbot-datasources-config"]
---

## dev-bot datasources `env` values support whole-value `${VAR}` references only

An `env` value in `.devbot.global.jsonc` is either a literal or a reference, and a reference must be the ENTIRE value — `ENV_REF_RE = ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$` in `render_tools_yaml.py`. Partial interpolation inside a longer string is not a reference: `"mongodb+srv://${USER}:${PASS}@${HOST}"` is treated as a literal and written verbatim into the rendered `tools.yaml`. Toolbox then performs its own `${...}` expansion, finds no such variables in the container, and refuses the whole config with `unable to parse config file … environment variables not found: "…" (line N, column M)`.

The fix is one variable holding the whole value — `"MONGODB_URI": "${MONGODB_PROD_DSN}"` with the complete connection string in the environment. The failure only appears at toolbox load/validation time and names the inner variables, so it reads like an auth or YAML problem rather than "this module does not interpolate".
