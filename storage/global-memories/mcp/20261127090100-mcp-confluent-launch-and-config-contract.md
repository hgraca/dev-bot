---
date: 2026-11-27
keywords: ["mcp", "mcp-confluent", "kafka", "allow-tools"]
aliases: ["confluent kafka mcp", "mcp-confluent config", "kafka mcp server"]
---

## mcp-confluent 1.6.1's launch and config contract

Verified by executing the pinned binary (`@confluentinc/mcp-confluent@1.6.1`, Node ≥ 22.23.4):

- `--config <yaml>` and `--transport <t…>` are **mutually exclusive when the transport comes from the CLI**; the pair exits 1 with "use server.transports in the YAML file instead". Omit `--transport` — stdio is the default.
- Credentials go in the connection's named **`auth`** block (`{type: api_key, key, secret}`), never in `kafka.extra_properties`: the schema refuses `sasl.username`, `sasl.password` and `bootstrap.servers` there. `extra_properties` is the override path (`sasl.mechanisms: SCRAM-SHA-512`, a non-default `security.protocol`); the server spreads it after the auth-derived defaults, so an override wins. `schema_registry` is strict — `endpoint` + `auth` only, no `extra_properties`.
- `read_only: true` is a per-connection flag that auto-disables every mutating tool by its `readOnlyHint` annotation — a second gate behind `--allow-tools`.
- `--allow-tools <csv>` **ignores an unknown name with a warning** rather than failing, so an upgrade that renames a tool shrinks the surface silently. Prove each allowlisted name survives with `--list-tools`.
- `${VAR}` and `${VAR:-default}` interpolate in every string value and **raise** when the variable is absent (`Environment variable not found: …`); `$${…}` is the literal escape.
- `--list-tools` is colourised (escapes between the indent, the name and the colon) — strip ANSI and set `NO_COLOR=1 FORCE_COLOR=0` before matching names. `--list-tools` shows the allow/block-filtered catalogue only; per-connection predicates decide what actually registers.
- `consume-messages` is annotated READ_ONLY and opens a **random-UUID consumer group per call** with auto-commit off: it never advances a real group's offsets, but each read registers a short-lived `mcp-confluent-<uuid>` group, so the principal needs group `Create`/`Read` on that pattern. `start` accepts `"earliest"`, `"latest"`, `{tail: N}`, `{offset: "…"}` and `{timestamp: …}` — `{tail: N}` and `{offset}` require `partition`.
- `get-topic-config` needs the Confluent Cloud REST fields (`rest_endpoint`, `cluster_id`, `env_id`) plus a named auth block; on a direct self-managed connection it **never registers**, so allowlisting it promises a tool that does not exist.
- `DO_NOT_TRACK=true` in the environment disables both telemetry and Sentry error reporting.
