---
date: 2026-08-06
keywords: ["otel", "ottl", "merge_maps", "transform", "flatten"]
trigger-on: ["flatten-nested-attributes", "context-map-to-attributes", "ottl-merge-maps"]
---

## Flatten nested attribute maps with OTTL merge_maps in transform processor

When a filelog `json_parser` creates a nested map in attributes (e.g. `attributes["context"]` = `{correlation_id: "...", sender: "..."}`), use a `transform` processor with OTTL to copy its keys into top-level attributes. The filelog operators run inside the receiver — by the time the transform processor runs, `attributes["context"]` is a proper `pcommon.Map` that `merge_maps` can consume directly. Use `"upsert"` strategy — context keys like `message` won't collide because `move-message-to-body` has already consumed `attributes.message`. Config:

```yaml
transform/flatten-context:
    error_mode: ignore
    log_statements:
        - context: log
          statements:
              - merge_maps(attributes, attributes["context"], "upsert") where attributes["context"] != nil
```

Wire it into the logs pipeline after `k8sattributes`, before `filter/exclude-annotated` and `batch`. This produces flat filterable attributes like `correlation_id`, `sender`, `message_id` alongside the original `context` JSON string.
