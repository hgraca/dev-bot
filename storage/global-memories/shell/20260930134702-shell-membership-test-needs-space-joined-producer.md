---
date: 2026-09-30
keywords: ["shell", "grep", "word-split", "separator", "bash"]
trigger-on: ["bash-list-membership-test", "shell-producer-consumer-separator"]
---

## A space-delimited membership test needs a space-joined producer

`printf ' %s ' "$list" | grep -Fq " $name "` matches only when `$list` is **space**-delimited. A producer that prints one value per line silently breaks it for two or more values, and — worse — passes for exactly one: `$(...)` strips the trailing newline, so ` wanted="a" ` yields the pattern ` a ` and matches by accident. The bug is invisible until a second value exists, which is exactly the state production reaches.

Seen live: `demand.py`'s names mode printed per-line while the consumer `grep`ed for `" ${svc} "`, so on a machine with two demanded sidecars **neither** matched and both were classified "unwanted" and stopped. Every test used one item and stayed green.

Rule: fix the separator once, on the producer, and state it in both docstrings (`space-joined`). Then test the reader with **two** values — a single-value test proves nothing. When in doubt, prefer an explicit membership helper over ad-hoc `grep` patterns, and remember `grep -w` is not a fix: it treats `-` as a non-word character, so a hyphenated name matches inside a longer one.
