---
date: 2026-11-15
keywords: ["devbot", "mcp", "env", "secret", "test"]
aliases: ["env reference resolved to plaintext", "secret leaked into .mcp.json", "{env:VAR} regression test"]
see: ["ADRs/20261115130000-modules-publish-runtime-mcp-manifests.md"]
---

# An `{env:VAR}` reference must reach a manifest as a reference — and the test must set the variable

`mcp_translate.py` maps a canonical `{env:VAR}` to opencode's `{env:VAR}` and to Claude Code's `${VAR}`; both clients expand it at launch. Any code path that instead reads `os.environ[...]` at registration writes the **secret itself** into `.mcp.json` — in this project a Sentry bearer token ended up in plaintext. The correct spelling is `_map_env_value` (whole-value env entries) and `_map_env_refs` (embedded header refs); never resolve, never leave the raw `{env:VAR}` for claudecode.

Regression-testing this is subtle: with the variable **unset**, an old resolver falls back to the literal token and produces the same `${VAR}` output, so the test stays green. Set the variable to a known sentinel in the test and `refute_output --partial "<sentinel>"` alongside asserting `${VAR}` — only then does reintroducing the resolver fail the suite.
