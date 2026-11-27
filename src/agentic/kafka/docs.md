---
title: "Kafka"
description: "Inspect a Kafka cluster from an agent — topics, partitions, consumer-group lag and a bounded message tail — one read-only MCP server per configured connection."
skills: ["kafka"]
---

Inspect a Kafka cluster from an agent: list topics, read partition watermarks,
find consumer groups and their lag, and read a bounded batch of messages from a
topic — through Confluent's MCP server, one instance per configured connection.

## What it does

Ships one skill (`devbot:kafka`) and wires `@confluentinc/mcp-confluent` into the
harness — **one server per connection**, named `kafka-<connection>`.

A Kafka **connection** is a broker address plus whatever authentication and
Schema Registry it needs. Connections are declared once in `.devbot.global.jsonc`
and each project opts in by name, so a machine can hold a staging and a production
connection and a project sees only the ones it selected. `devbot init`/`reinit`
wires and prunes the servers, and nothing is prompted at install time.

The launcher is also an operator tool: `--which` reports the installed server,
`--print-config <connection>` prints the rendered config for one connection, and
`--check <connection>` renders it and proves the installed server accepts it.

## Read-only by construction

Every launch passes `--allow-tools` with a fixed list, and the rendered config
carries `read_only: true`, which disables every tool the server annotates as
mutating. `produce-message`, `create-topics`, `delete-topics` and
`alter-topic-config` are therefore unreachable twice over — the allowlist never
names them, and the connection would refuse them anyway. That second gate is
what keeps a future upgrade that adds a write tool from making it callable.

`get-topic-config` is not in the list: its predicate needs the Confluent Cloud
REST fields, so it never registers on a direct Kafka connection. Widening the
list is a deliberate edit to `ALLOWED_TOOLS` in `src/agentic/kafka/functions.sh`,
not a config option.

`consume-messages` is safe against a live cluster: it is annotated read-only and
opens a **random consumer group per call** with auto-commit off, so it never
joins a deployed group and never advances its offsets. Two consequences worth
knowing:

- each read registers a short-lived group named `mcp-confluent-<uuid>` in the
  cluster's group list — the very surface `list-consumer-groups` shows — so a
  few of them may linger for the broker's retention window;
- that means the principal needs `Create`/`Read` on group names under
  `mcp-confluent-*` in addition to topic `Describe`/`Read`. A principal
  provisioned for admin-only access will fail the read, not the listing.

Its "bounded read" is literal — it returns up to `maxMessages` within `timeoutMs`
and stops; the agent continues from the offsets it received. The skill documents
that cursor loop.

## Configuration

| Key                 | Where                   | Meaning                                         |
| ------------------- | ----------------------- | ----------------------------------------------- |
| `kafka_connections` | `.devbot.global.jsonc`  | catalogue — a name mapped to a connection       |
| `kafka_connections` | `.devbot.project.jsonc` | list of connection names this project opts into |

A connection names its broker and, optionally, its credentials and Schema
Registry:

```jsonc
// .devbot.global.jsonc
"kafka_connections": {
  "staging": {
    "bootstrap_servers": "broker.staging.get-e.local:9092",
    "auth": {
      "type": "api_key",
      "key": "${DEV_KAFKA_STAGING_USER}",
      "secret": "${DEV_KAFKA_STAGING_PASS}"
    },
    "extra_properties": { "sasl.mechanisms": "SCRAM-SHA-512" }
  }
}
```

| Field               | Meaning                                                                                                                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `bootstrap_servers` | required — the broker list the client connects to                                                                                                                                                |
| `auth`              | optional — `{type: "api_key", key, secret}`, the server's named credential block; omit it for an unauthenticated broker                                                                          |
| `extra_properties`  | optional — librdkafka client properties passed through verbatim; `sasl.username`, `sasl.password` and `bootstrap.servers` are **refused** here, since the server keeps those in the named fields |
| `schema_registry`   | optional — `endpoint` (http/https) plus its own optional `auth`; its presence is what makes `list-schemas` and payload decoding exist                                                            |

A credential is named **once**, in the catalogue: the launcher resolves the
reference from the process environment and then the repo `.env`, so
`${DEV_KAFKA_STAGING_PASS}` above is the only place that variable is mentioned.

A named `auth` block implies `security.protocol: SASL_SSL`. For SASL/PLAIN over
TLS only the mechanism differs — `extra_properties: {sasl.mechanisms: PLAIN}`.
A plaintext setup (`SASL_PLAINTEXT`, or a local broker with no auth) needs
`security.protocol` overridden in `extra_properties`; the server spreads
`extra_properties` after the auth-derived defaults, so the override wins.

The `kafka` **module** must also be enabled (`modules.kafka: true`); the shipped
global template defaults it to `false`, and a disabled module's init never runs.
A connection that is declared but not selected is not wired; a selected
connection that is not declared — or one whose entry does not render, or that the
installed server rejects — warns and is **not** wired, and a manifest an earlier
init published for it is retired.

On opencode each generated manifest ships the server with `enabled: false` (wired
but not started); flip it to `true` in `opencode.jsonc`, or toggle it in the
harness. Claude Code has no per-server switch: a `wire_disabled` entry is omitted
from `.mcp.json` entirely, so a Kafka connection is not available there without
changing the module's `init.sh`.

## Credentials

Nothing secret belongs in a dev-bot config file: `auth` and `extra_properties`
carry **`${VAR}` references**, and that is the only place a variable is named.
The launcher resolves each one — from the process environment first, then the
repo `.env` (gitignored) — and writes the value into the rendered config. There
is no second mapping layer to keep in step.

A reference that resolves to nothing refuses the launch and names the variable and
the connection — the server itself raises on a missing variable rather than
connecting anonymously, so a half-filled `.env` fails loudly instead of silently
listing no topics.

The launcher **parses** the repo `.env` for the references it needs and hands the
server nothing but its own wrapper settings, so the process never inherits the
unrelated database, cloud or signing credentials a repo `.env` usually holds.
Nothing in the file is executed: it is read as data, which also makes a stray
shell snippet in it harmless. The reader is line-oriented, the same shape Docker
Compose's `.env` has — a value that spans lines is not supported, so keep a
credential on one line (a newline in one is truncated at the first line).

The rendered config is written to `storage/kafka/<connection>-<hash>.yaml` (mode
0600 under a 0700 directory, gitignored) on every launch, and it holds the
**resolved** values: that file is the one place a credential sits. The name is
content-addressed, so two launches whose resolved configs differ — another
project, another set of credentials — write different files and cannot swap
credentials under each other between the render and the server's read. Values
are inserted as YAML data, never as text, so a quote or a newline in a credential
cannot reshape the document. The digest is SHA-256, so two different credential
sets cannot collide into one file, and a file is pruned once it is an hour old and
no longer the one a launch is writing — the server parses its config at startup,
so that window is what keeps a launch that is still reading safe. Nothing reaches the
server's argv (readable through `ps`) or its environment, which is scrubbed to
`PATH`, `HOME`, `TMPDIR`, `LANG` and `DO_NOT_TRACK`. Treat
`storage/kafka/<connection>.yaml` as a secret — and note that
`kafka-mcp-launch.sh --print-config <connection>` prints the **unresolved**
document on purpose, so inspecting a connection does not spill its credentials
into a terminal or a log.

## Watching events during development

`consume-messages` is a bounded read, not `tail -f`. The agent reads a batch —
the last N on a partition (`{ tail: N }`), everything from `"latest"`, an offset,
or a timestamp — reports what it saw, and continues per partition from
`lastOffset + 1` when asked. Two empty batches mean the topic is idle, not that
the cursor is wrong. The skill carries the loop's rules, including why the offset
must advance per partition.

## Prerequisites

`install.sh` installs `@confluentinc/mcp-confluent` at the pinned version
(`versions.env`, bumped by `devbot update`) with npm, and refuses to install
below the package's Node floor. `update.sh` proves the new version still
advertises every allowlisted tool before moving the pin — `--allow-tools` ignores
an unknown name with a warning, so a rename would otherwise shrink the surface
silently — and puts the previous version back when one disappeared. The launcher
execs the installed binary rather than `npx`, so a session never waits on a
dependency resolution it did not ask for, and sets `DO_NOT_TRACK=1` so the
server sends no telemetry.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Datasources](/modules/agentic/datasources) — database and Redis data access
- [AWS](/modules/agentic/aws) — the per-connection credential pattern this module follows
