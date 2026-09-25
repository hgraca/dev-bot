---
date: 2026-09-23
keywords: ["signoz", "trace-parser", "trace_id", "attribute-collision", "otel-collector"]
trigger-on: ["otel-filelog-trace-parser", "signoz-ambiguous-field"]
---

## Promotion operators leave the source attribute behind, so SigNoz catalogues one key in two contexts

Stanza's `trace_parser` — and any promotion-style operator — copies an attribute into a record-level field **without removing the attribute it read**. `trace_id: {parse_from: attributes.trace_id}` therefore leaves `attributes.trace_id` on the record, so every log carries both `trace_id` in the log context and `trace_id` in the attribute context. SigNoz catalogues both, and a filter such as `trace_id = '<id>'`, or a bare `searchText`, silently matches only the context the query resolved to — returning a subset with no error, which reads as "there are no such logs". `span_id` behaves identically. This is permanent, not a lag: it holds for every newly ingested record, unlike a field the collector stopped emitting, which lingers in the catalog only until the retention TTL retires the pre-fix rows.

Fix it downstream of the promotion — in a processor that runs after the receiver's operators — with `delete_key(attributes, "trace_id") where attributes["trace_id"] != nil`. Deleting is safe because the record-level `trace_id` the parser produced is what correlation reads; only the redundant copy goes.

Verify against a **recent window**, never the field catalog: `attribute.trace_id EXISTS` over the last 5–10 minutes must be 0 after the agent pods roll. The catalog lists a removed key for as long as old rows live, so it will keep showing the collision for days and looks like the fix failed.
