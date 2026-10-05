---
date: 2026-10-05
keywords: ["devbot", "datasources", "opensearch", "sidecar", "basic-auth"]
trigger-on: ["datasources-sidecar", "opensearch-datasource"]
---

## OpenSearch datasource sidecar: basic-auth credentials must ride inside the URL

The `datasources` module's `opensearch` sidecar accepts only five `env` keys — `OPENSEARCH_URL`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (the `SIDECARS` allow-list in `src/agentic/datasources/render_tools_yaml.py`, enforced loudly by `_validate_sidecar_env`). The upstream `opensearch-mcp-server-py` does support `OPENSEARCH_USERNAME` / `OPENSEARCH_PASSWORD`, but they are **not** on that allow-list, so a cluster using basic auth rather than AWS SigV4 cannot be configured with separate credential variables — the username/password must be embedded in the `OPENSEARCH_URL` value (e.g. `https://user:pass@host`) and referenced whole as `"OPENSEARCH_URL": "${MY_OS_URL}"`. An AWS SigV4 OpenSearch connection instead takes `AWS_REGION` + `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (+ optional `AWS_SESSION_TOKEN`). Sidecars bypass the toolbox canary in `validate_catalogue.py` (passed through unprobed), so a datasource catalogue can be validated offline, without docker or a live cluster, by piping it through the renderer: `python3 src/_shared/read_jsonc.py <global.jsonc> datasources | python3 src/agentic/datasources/render_tools_yaml.py` (exit 0 = every name, type and env key accepted).
