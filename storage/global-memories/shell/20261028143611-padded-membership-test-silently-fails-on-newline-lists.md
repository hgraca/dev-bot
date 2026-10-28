---
date: 2026-10-28
keywords: ["shell", "grep", "newline", "pipefail"]
---

## A space-padded `grep` membership test silently matches only single-entry lists

The idiom `printf ' %s ' "$list" | grep -Fq " $name "` tests membership in a **space-joined**
list. Point it at a list produced one-item-per-line and it fails for every entry except the last
one — the pattern wants `" name "` but the text has `" name\n"`. The failure is silent and
one-sided: it reports a false negative, never an error.

Worse, the bug hides in tests: command substitution strips the trailing newline, so a
single-entry list becomes `" name "` and matches. Any test whose fixture happens to leave exactly
one entry passes while production, with two or more, breaks.

Real case: `_published_sources` and `_sidecar_services` emitted newline-separated names, and
`_unpublished_selected` compared them with the padded pattern — so with 2+ served datasources every
one was reported "unpublishable" and the command always exited 1.

Fix at the comparison, not the producer: `printf '%s\n' "$list" | grep -Fqx "$name"` is
separator-agnostic and cannot regress this way. When you keep the padded idiom, the producer must
be space-joined by contract and documented as such. Cover it with a fixture that has **two or more**
entries — that is the shape the bug lives in.
