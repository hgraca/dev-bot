---
date: 2026-09-26
keywords: ["shell", "bash", "parameter-expansion", "json"]
trigger-on: ["bash-default-value-braces"]
---

## `${x:-{}}` appends a literal `}` — brace defaults need a variable

In `${x:-{}}` bash closes the expansion at the first `}`, so the value is `"${x:-{}"` concatenated with a literal `}`, and a non-empty `x` yields `value}`. The failure is silent when the result is only read by a human and corrupting when it is parsed: `ports="${ports:-{}}"` turned valid JSON (`{"a": 18520}`) into `{"a": 18520}}`, and the caller's `json.loads` fell back to "no data" — the tool appeared to return nothing rather than malformed data. Use an explicit branch (`if [[ -z "$x" ]]; then echo "{}"; else echo "$x"; fi`) or keep the default in a variable (`default="{}"; echo "${x:-$default}"`). ShellCheck does not flag it.
