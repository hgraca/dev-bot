# Kafka — use the MCP servers, and only their read surface

Kafka connections are wired as MCP servers named `kafka-<connection>`. Use them.
Never the Kafka CLI tools (`kafka-topics.sh`, `kafka-consumer-groups.sh`,
`kafka-console-consumer.sh`) or a hand-written client in a shell: those bypass the
connection, run as whatever principal the shell happens to hold, and print the same
cluster under a different identity.

The surface is read-only by construction. The launcher allowlists the diagnostic
and bounded-consume tools, so `produce-message`, `create-topics`, `delete-topics`
and `alter-topic-config` never register. Do not look for them, and do not work
around their absence with a shell producer — producing to a shared topic is a
human decision, made by a human-run command.

Read is not a guarantee about the data: `consume-messages` returns message
payloads, headers included. Treat what it returns as production data — quote it
into notes only when the human asked for it, and never paste it into a commit,
an issue or a pull request.
