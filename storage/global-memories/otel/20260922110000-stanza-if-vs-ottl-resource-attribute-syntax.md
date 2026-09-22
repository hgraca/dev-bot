---
date: 2026-09-22
keywords: ["otel", "stanza", "if-expression", "ottl", "filelog"]
trigger-on: ["otel-receiver-operator-guard", "stanza-if-expression", "ottl-resource-attributes"]
---

## Inside a receiver operator, resource attributes read `resource["key"]` — not `resource.attributes["key"]`

The same attribute has two different access paths depending on the OTel Collector layer, and using the wrong one in a receiver operator fails in a way that looks like the rule silently does nothing. In an **OTTL processor** (`transform`, `filter`) the path is `resource.attributes["k8s.container.name"]`; in a **stanza operator** `if:` expression (filelog receiver operators) it is `resource["k8s.container.name"]` — the entry's resource-*attributes* map is still nil at operator time, so `resource.attributes[…]` logs `cannot fetch k8s.container.name from <nil>` **for every record** while still forwarding the entry. Verified by running four syntaxes side by side against contrib 0.139.0: only `resource[…]` matched, `attributes[…]` was absent, and `attributes["log.file.path"] matches "/gotenberg/"` also worked. Practical corollaries: the filelog `container` operator is what produces the container metadata, and it needs `include_file_path: true` on the receiver (otherwise: "has 'add_metadata_from_filepath' enabled, but the log record attribute 'log.file.path' is missing") plus a real `/var/log/pods/<ns>_<pod>_<uid>/<container>/<n>.log` path (all three underscore-separated parts) and a CRI-prefixed line (`<ts> <stream> <tag> <message>`) or it fails with "entry cannot be parsed as container logs"; and `service.name` is set later still, by `k8sattributes`, so a receiver operator cannot guard on it at all.
