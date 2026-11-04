---
date: 2026-11-04
keywords: ["git", "sparse-checkout", "no-cone", "partial-clone"]
---

## `sparse-checkout set --no-cone` needs git 2.35, not 2.25

`git sparse-checkout` arrived in 2.25, but `sparse-checkout set --no-cone` only arrived in 2.35 (2.34's `set` accepts `--stdin` only). A feature gate that accepts 2.25 therefore passes on Ubuntu 20.04/22.04 and Debian 11, then fails at `set --no-cone` — and a fallback that runs `sparse-checkout disable` silently materializes the whole tree, turning the optimisation into an extra full fetch on every run. Gate on `>= 2.35`, and make a failed `set` explicitly restore the full tree.
