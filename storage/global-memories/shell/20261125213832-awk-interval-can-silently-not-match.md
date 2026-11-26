---
date: 2026-11-25
keywords: ["shell", "awk", "regex", "interval-expresssion", "bats"]
aliases: ["awk {3,4} does not match", "awk interval expression", "awk reads to EOF"]
---

## An awk `{m,n}` interval can silently fail to match, turning a section parser into "read to EOF"

A parser written as `awk '… /^#{3,4} /{exit} …'` looks correct and is not portable: whether `{3,4}`
is honoured depends on which awk is installed. Where it is not, the stop condition never fires, the
parser reads the rest of the file, and the result looks plausible — a section that should hold nine
lines reports 76, and a guard built on a minimum count still passes because the inflated number clears
the threshold. The failure is silent in exactly the direction that hides a defect.

Prefer a positional test that cannot degrade: `substr($0, 1, 3) == "###"` for "a heading at column 1",
or `index($0, prefix) == 1`. In awk, `index` and `substr` behave identically everywhere.

Prove the parser before trusting a guard built on it: run the extraction over one known section and
eyeball the number (`A04 → 10`), and run it over a synthetic two-line file that should yield zero. A
guard that passes on both is doing its job; one that passes on everything is reading to EOF.
