---
date: 2026-10-12
keywords: ["devbot-init", "mdctx", "module-init-order", "memory-vault"]
---

# Module init.sh scripts run in glob order — a consumer can run before its producer

`bin/init.sh` runs each module's `init.sh` through `_run_module_script`
(`src/_shared/functions.sh`), which iterates `${base_dir}/`*/ — an
**alphabetical glob order, not a declared dependency graph**. So a module whose
`init.sh` consumes another module's output can silently run first.

## Concrete trap (fixed in `f3e039a5`)

`mdctx` sorts before `memory`. `mdctx/init.sh` builds the per-project index over
`<devbot-dir>/memory/latent`, but that vault is scaffolded by
`memory/init.sh`. On a fresh `devbot init`, mdctx ran first, found no latent
directory, and printed a warning then `exit 0` — skipping the project index
build for that run.

`qmd` carries the *same* latent check but sorts **after** `memory` (`q` > `m`),
so it never hit the trap. The defect was latent and masked purely by alphabet.

## Fix

`mdctx/init.sh` now creates `<devbot-dir>/memory/latent` with `mkdir -p` when
it is missing, instead of warning. The memory module seeds the subdirectories
(`ADRs/PDRs/learnings`) moments later, so the final tree is complete; the empty
first index is correct because a fresh vault holds only `.gitkeep` files.

## Rule

A module whose `init.sh` needs an input directory must **create it**, never
assume a sibling module already ran — glob order is not a contract. When adding
an indexer or any consumer module, check where it sorts relative to its
producer.
