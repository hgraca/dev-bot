---
date: 2026-06-15
keywords: ["otel", "ottl", "transform"]
---

## OTTL function gotchas in collector 0.115.x

In OTel collector 0.115.1:

- **String replacement**: only `replace_pattern(target, regex, replacement)` is valid. Neither `ReplacePattern` nor `replace_all_strings` exist — both produce `undefined function` errors. `replace_pattern` is a standalone mutating function (no `set()` wrapper). For simple prefix/suffix removal, use regex: `replace_pattern(attributes["host.name"], "^ip-", "")`. In YAML config files, write regex `\.` as `\\.` (YAML escaping of backslash).

- **Avoid `Concat` — prepend text via start-anchor replacement**: `Concat` in collector 0.115.x requires list-typed arguments and fails with scalars or nested calls. For string prepend, use `replace_pattern` matching the zero-width `^` anchor: `replace_pattern(attributes["host.name"], "^", "staging-")`. Backreferences (`$1`) in the replacement string don't work — if the regex captures content, it must be re-inserted manually or via a different approach. This method inserts the prefix without affecting the existing value.
