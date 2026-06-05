---
date: 2026-06-18
keywords: ["shell", "grep", "eval", "escaping"]
---

## grep `$` escaping through eval chain in bash verification scripts

When using a `check()` helper with `eval "$2"` to run grep commands in bash, any `$` in the grep pattern silently expands to an empty variable through eval, producing wrong patterns. Use outer double quotes with `\\\\\$` escaping: `check "desc" "grep -q '\\\\\$PATTERN' file"`. The `\\\\\$` in double quotes becomes `\\\$`, then inside single quotes grep sees literal `\$` (matches `$` in BRE). Without this chain, `$PATTERN` becomes empty and grep matches nothing silently. See `verify-otel.sh` in the exchange-rate repo for working example — the incorrect alternativè `'grep -q "\\\\\\$PATTERN"'` (outer single quotes) expands `$PATTERN` to empty inside eval double quotes.
