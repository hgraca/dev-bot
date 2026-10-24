---
date: 2026-10-24
keywords: ["shell", "bash", "nounset", "local", "unbound-variable"]
aliases: ["local a b=0", "unbound variable under set -u", "nounset local declaration"]
---

## `local a b=0` leaves `a` unset under `set -u`

In bash 5.2, `local a b=0` declares both names but assigns only `b`; `a` stays unset rather than empty, so a later `${a}` aborts with "unbound variable" under `set -u` even though `local` named it (`${a-UNSET}` prints `UNSET`, which is how it surfaces). Declare every name with an explicit empty value — `local a="" b=0` — whenever the function can be short-circuited before assigning it. In practice the symptom is a variable declared in one branch of a long function reported unbound in a later branch, with the error pointing at the use and nothing wrong-looking at the declaration.
