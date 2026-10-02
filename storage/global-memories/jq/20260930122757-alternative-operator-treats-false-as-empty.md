---
date: 2026-09-30
keywords: ["jq", "alternative-operator", "false", "default"]
trigger-on: ["jq-alternative-operator", "jq-default-value"]
---

## jq's `//` alternative operator treats `false` as empty

`a // b` yields `b` when `a` produces `null` **or `false`, not only when it is missing** — so `.send_resolved // true` returns `true` even when the field is explicitly `false`. In `scripts/setup-alerts.sh` this made the payload builder unable to ever write `send_resolved: false`, flipping the three Slack channels the apply rewrites to `true` while the other fifteen kept their manually-set `false` — which is what made the bug look intermittent. Default only on `null`, with an explicit check: `(if .send_resolved == null then true else .send_resolved end)`. The same trap bites the read side of a comparison, e.g. `[.name, (.send_resolved // true)]` reporting `true` for a manifest that says `false`. When the value can legitimately be `false`, use `has("key")` to tell absent from `false` instead of `//`.
