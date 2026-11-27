---
name: devbot:kafka
description: "Use when inspecting a Kafka cluster from an agent — topics, partitions, consumer-group lag, or tailing messages on a topic during development. Triggers on 'kafka', 'topic', 'consumer group', 'consumer lag', 'partition offsets', 'tail the queue', or a broker address."
---

# Kafka

The module wires one MCP server per configured **connection**, named
`kafka-<connection>`. Everything below goes through those servers; the Kafka CLI
tools are off limits (see `memory/active/modules/kafka.md`).

## The tool surface

The launcher allowlists what the server may register, so this is the whole
surface — if a tool is not listed here it does not exist in this session:

| Tool                      | Answers                                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| `list-topics`             | which topics exist                                                                                 |
| `get-partition-offsets`   | low/high watermark and message count per partition — "how big is this topic", "what offsets exist" |
| `list-consumer-groups`    | which groups exist, and their state                                                                |
| `describe-consumer-group` | members, assignment, protocol for one group                                                        |
| `get-consumer-group-lag`  | per-partition committed offset vs high watermark — the lag number                                  |
| `consume-messages`        | a bounded read of records from a topic                                                             |
| `list-schemas`            | Schema Registry subjects (only when the connection has one)                                        |
| `explain-disabled-tools`  | why a tool you expected is absent                                                                  |

The writes (`produce-message`, `create-topics`, `delete-topics`,
`alter-topic-config`) are deliberately unregistered. A request for one is a
human decision: say what you would run and stop.

## Diagnostics — the question, then the tool

Start from the symptom, not from a topic list:

- **"Is it stuck?"** → `list-consumer-groups` for the group's state, then
  `get-consumer-group-lag`. Lag alone is not a fault: a group that is
  `Stable` and consuming at a steady lag is healthy. A group that keeps lag
  climbing with `Stable` state is the real signal — compare two readings a
  minute apart.
- **"Are messages arriving?"** → `get-partition-offsets` twice. A rising high
  watermark means the producer is fine and the consumer is the suspect; a flat
  one means nothing is being written.
- **"Which topic is this?"** → `list-topics` (it takes no filter — read the
  list and pick the fragment yourself), then `get-partition-offsets` for its
  size. Retention and cleanup policy are not reachable through this surface:
  `get-topic-config` needs the Confluent Cloud REST fields, so it is not
  allowlisted. Say so instead of guessing at a retention setting.
- **"Why can't I see topic X?"** → `explain-disabled-tools`. An empty
  `list-topics` usually means the connection points at another cluster, not
  that the topic is gone.

Always name the connection you queried in the answer. Two connections in one
session is normal, and a lag number from the wrong cluster is worse than no
number.

## Tailing messages during development

`consume-messages` is a **bounded read**, not a tail: it returns up to
`maxMessages` (default 10) within `timeoutMs` (default 10s) and then stops.
Driving a live tail is therefore a cursor loop you control.

`start` is one of:

- `"latest"` — only what is produced while the call runs (default: `"earliest"`,
  the whole retained history);
- `{ tail: N }` — the last N **already-written** messages on that partition,
  returned immediately without waiting for traffic. This is the one to reach for
  when a human says "show me what just landed";
- `{ offset: "1042" }` — an absolute partition offset (requires `partition`);
- `{ timestamp: "2026-05-14T17:00:00Z" }` — the broker's offset for that instant.

`{ tail: N }` and `{ offset: … }` are single-partition, so `partition` must be on
the same topic entry:

```text
consume-messages { topics: [{ name: "orders", partition: 0, start: { tail: 20 } }], maxMessages: 20 }
→ records, each carrying topic, partition, offset, timestamp
```

To keep following, continue from where it stopped:

```text
consume-messages { topics: [{ name: "orders", partition: 0, start: { offset: "1042" } }], maxMessages: 20 }
```

Rules that make that loop correct:

- **Advance per partition**, to `lastOffset + 1` on that partition — never from
  the highest offset across the topic, which silently skips other partitions.
  Offsets arrive as strings and `offset` must be a digit-only string; do
  arithmetic on `Number(...)` and send the result back as a string.
- **The read never commits and never joins the real group**: the server opens a
  random consumer group per call with auto-commit off, so it cannot disturb a
  deployed consumer's offsets. It is safe to point at a live cluster — but each
  read does register a short-lived `mcp-confluent-<uuid>` group in the cluster's
  group list, and the principal needs `Create`/`Read` on group names under
  `mcp-confluent-*`. A read that fails with a group authorisation error is that,
  not a connection problem.
- **Two consecutive empty reads mean "idle"**, not "broken" — report which
  topic, partition and offset you resumed from, so the human can tell a quiet
  topic from a wrong cursor.
- **Do not poll in a loop to "watch"**. Each call is a request the human pays
  for: read a bounded batch, show it, and ask whether to continue from the
  cursor you now hold.

Payloads are production data. Summarise by default (key, offset, a shape); show
whole values only when the human asked for them.

## Connections

Declared once in `.devbot.global.jsonc`, opted into per project by name:

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

```jsonc
// .devbot.project.jsonc — opt in by name
"kafka_connections": ["staging"]
```

Credentials go in the named `auth` block — the server refuses `sasl.username`,
`sasl.password` and `bootstrap.servers` in `extra_properties`. `extra_properties`
is the override path for everything else librdkafka accepts, `sasl.mechanisms`
(SCRAM) most often. Every `${VAR}` is resolved by the launcher from the process
environment and the repo `.env`, so the variable is named once — here — and
never repeated. A reference that resolves to nothing refuses the launch instead
of connecting as nobody.
