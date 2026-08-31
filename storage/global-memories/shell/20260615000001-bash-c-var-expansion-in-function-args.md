---
date: 2026-06-15
keywords: ["shell", "bash", "quoting"]
---

## bash -c variable expansion breaks when single-quoted inside "$@" function args

When a shell function passes a `bash -c` command via `"$@"`, any variable references inside single-quoted strings in the `-c` argument are NOT expanded — `bash -c '! grep -q "x" "$CM"'` sees literal `$CM` inside single quotes, which resolves to empty string inside the `bash -c` subprocess. Fix: use double quotes for the outer `-c` string so shell expands the variable first: `bash -c "! grep -q 'x' '$CM'"`. The inverted quote order (outer double, inner single) lets the calling shell expand `$CM` while the single quotes inside keep the grep pattern literal. This trap is especially easy to miss when combined with function argument splitting via `"$@"` because the quoting looks correct at a glance.
