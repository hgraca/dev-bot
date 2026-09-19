---
date: 2026-09-19
keywords: ["datasources", "mcp-toolbox", "mongodb", "timeout", "uri"]
---

# Bound a mongodb datasource through its URI — and the pathless-URI trap

The mcp-toolbox `mongodb` source has **no timeout field**: both `timeout` and `dialTimeout` are rejected as unknown, exactly as they are for `redis`. Its driver's default server selection is **30s**, so an unreachable host neither becomes ready inside the canary budget nor exits — the same unattributable hang `mysql` had, and the reason a mongo datasource pointing at a down server could stall a whole render. The only lever is the connection string: `connectTimeoutMS` + `serverSelectionTimeoutMS` (2000 each, matching the SQL engines' 2s dial bound) make the driver fail in ~2s and name the source.

Two traps, both hit for real:

- **A URI with no path cannot take a query.** `mongodb://localhost` + `?opt=1` is rejected with `error parsing uri: must have a / before the query ?`. A `/` must be inserted first (`mongodb://localhost/?opt=1`). Every committed unit test passed while this was broken, because the fixtures used well-formed URIs (`mongodb://host:27017/db`) — the real-container e2e is what caught it. Test the shapes a user actually writes: bare host, `host:port`, `host/`, `+srv`.
- **The separator follows the URI, not a convention.** With an existing query it must be `&`, otherwise `?`. That can be decided for a `${VAR}` reference because toolbox substitutes `${VAR}` **mid-string** (verified against the pinned image: `uri: ${MONGO_URL}?connectTimeoutMS=2000` resolves and the parameter applies) — so the suffix is appended to the reference while the value itself is never written to disk. When the variable cannot be read, leave the URI untouched rather than risk corrupting it.

A parameter the operator already set is never overwritten — which doubles as the escape hatch: put `serverSelectionTimeoutMS` in your own URI for a cluster that honestly needs longer.

Implementation: `_uri_timeout_suffix` / `_uri_has_path` / `_uri_query_keys` in `src/agentic/datasources/render_tools_yaml.py` (engine key `uri_timeout_params`).
