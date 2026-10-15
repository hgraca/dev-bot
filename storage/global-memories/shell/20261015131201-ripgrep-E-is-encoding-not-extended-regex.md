---
date: 2026-10-15
keywords: ["shell", "ripgrep", "rg", "verification", "flags"]
aliases: ["rg -E unknown encoding", "ripgrep extended regex flag"]
trigger-on: ["ripgrep-invocations", "verification-greps"]
---

## ripgrep's `-E` is `--encoding`, not `grep -E`'s extended regex — a wrong flag verifies nothing

`rg -nE 'get-e|herberto'` fails with `rg: error parsing flag -E: unknown encoding: get-e|herberto`, because ripgrep's `-E` sets the input encoding and consumes the next argument as its value; it is not the extended-regex switch it is in `grep`. The failure mode is worse than a plain error: in a shell chain like `rg … || echo "none ✓"`, the non-zero exit makes the fallback print the reassurance, so a leak check that never ran reports success — the same inversion as `grep -q` under `pipefail`. Ripgrep patterns are extended-regex by default, so drop the flag entirely (`rg -n 'a|b'`). More generally, whenever a command's output _is_ the evidence, read the status explicitly (`rg -n 'pat' .; echo "exit=$?"`) rather than letting an `||` fallback speak for it, and treat an unexpected "clean" result as a prompt to confirm the check actually ran.
