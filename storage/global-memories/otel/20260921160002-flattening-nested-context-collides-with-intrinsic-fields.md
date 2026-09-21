---
date: 2026-09-21
keywords: ["otel", "ottl", "merge-maps", "attribute-collision", "log-body"]
trigger-on: ["otel-flatten-context", "merge-maps-attributes", "collector-attribute-collision"]
---

## Flattening a nested context map into log attributes collides with intrinsic field names

`merge_maps(attributes, attributes["context"], "upsert")` is a common way to make an application's structured log context filterable, but the context keys are unconstrained and can shadow intrinsic log fields. A context carrying a `body` key (any API-response payload named that way) is promoted to `attributes["body"]`, which then collides with the log record's own `body` — yielding a `Key body is ambiguous` warning and unreliable `body` filters. `merge_maps` offers no exclude list, so normalise explicitly after the merge: preserve the value under a namespaced key, then drop the top-level copy — `set(attributes["context.body"], attributes["context"]["body"]) where attributes["context"] != nil and attributes["context"]["body"] != nil` followed by `delete_key(attributes, "body") where attributes["context.body"] != nil`. Both guards matter: the first makes the rename a no-op when there is no context body, and the second stops the delete from removing a legitimate top-level application `body` attribute. Also note `delete_key(attributes, "body")` touches only *attributes* — the log record's own body is a separate field and is untouched.
