---
date: 2026-10-15
keywords: ["signoz", "api", "json", "grep", "jq"]
aliases: ["u003e escaping", "html escaping in api responses", "grep misses rule threshold"]
trigger-on: ["signoz-api-scripting", "signoz-rule-inspection"]
---

## The SigNoz API HTML-escapes `<`, `>` and `&` in its JSON responses

The SigNoz v2 routes are served by Go's `encoding/json`, which HTML-escapes `<`, `>` and `&` as
`\u003c`, `\u003e` and `\u0026` unless the encoder explicitly disables it. A rule's ClickHouse query
therefore comes back with `WHERE c >= 50` encoded as `WHERE c \u003e= 50`, so
`curl -s "$SIGNOZ_URL/api/v2/rules" | grep -o 'c >= [0-9]*'` prints **nothing** — which is
indistinguishable from the value genuinely being absent. A verification built on that grep reads as
a failure while the change is in fact live.

Parse with `jq` first (it decodes the escapes) and scan the decoded string:

```bash
curl -s "$SIGNOZ_URL/api/v2/rules" -H "SIGNOZ-API-KEY: $SIGNOZ_AUTH_TOKEN" \
  | jq -r '.data[] | select(.alert|test("logs growth"))
      | "\(.alert) floor=\([.condition.compositeQuery.queries[0].spec.query | scan("c >= [0-9]+")]|join(","))"'
```

The same applies to any `<`/`>`/`&` in a query, a filter expression, or a URL stored in a response
field. Grepping a SigNoz API response raw is only safe for characters Go does not escape.
