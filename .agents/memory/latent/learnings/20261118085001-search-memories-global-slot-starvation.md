---
date: 2026-11-18
keywords: ["devbot", "search-memories", "mdctx", "ranking", "global-memories"]
---

# Project-first ranking made the global store unreachable at the default window

## Symptom

`search-memories` returned only project-vault hits for a query whose exact note lives in `storage/global-memories/` — 0 global hits at `--max-results 8`, 2 at `--max-results 30`, same query. `mdctx search -i storage/.mdctx/context-index.json` ranked the global note **first**, so neither the index nor the store was at fault.

## Cause

`search_mdctx()` concatenated `ordered + global_results + custom_results` and truncated to `max_results` (the audit-53 project-first merge). A project vault with at least `max_results` matches fills every slot, so the 1,365-note shipped store is unreachable at the default 5: the guarantee "the project vault is never silent behind global noise" had become "global is never visible at all".

## Fix

Reserve one slot for the non-project stores whenever they have a hit (`max_results > 1`); a single-slot window still goes to the project vault. Verify a ranking change on the **default** window, not only a large one — the bug is invisible at `--max-results 30`, where the same code looks correct.
