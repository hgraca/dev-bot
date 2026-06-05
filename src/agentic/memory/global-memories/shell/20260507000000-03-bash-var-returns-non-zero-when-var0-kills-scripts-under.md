---
date: 2026-05-07
keywords: ["shell", "bash"]
---

## Bash `((var++))` returns non-zero when var=0 — kills scripts under `set -e`

The arithmetic post-increment `((PASS++))` evaluates to the OLD value of `PASS`. When `PASS=0`, that's `0`, which bash treats as exit code 1 (false). Under `set -e`, the script aborts on the very first counter increment. Easy to miss because the line LOOKS innocent.
Fix: Use `PASS=$((PASS + 1))` (assignment never returns non-zero), or guard with `|| true`, or use pre-increment `((++PASS))` which evaluates to the NEW value (only fails when var was -1).
