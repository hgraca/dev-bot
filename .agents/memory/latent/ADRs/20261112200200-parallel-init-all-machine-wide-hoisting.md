---
date: 2026-11-12
keywords: ["init", "parallel", "concurrency", "flock", "deferral"]
see: ["learnings/20261112200000-worktree-git-is-a-file-rebase-state.md"]
---

## `init --all` fans out by hoisting the machine-wide writes into parent passes

Per-project wiring writes three machine-wide artifacts — the global project registry (`add_project.py`), the shared memory index/collection, and the external-module mirror prune — which is why the loop stayed serial. The decision is to fan out with bounded concurrency (`-j`/`--jobs`, default half of `nproc`, min 2, max 16; `-j 1` keeps the byte-identical serial path) and move those three writes out of the workers. Workers run with `DEV_BOT_DEFER_GLOBAL_{REGISTRATION,MEMORY,PRUNE}` exported; the parent runs the registry batch and the shared-store registration **before** the fan-out (so every worker's wiring hash sees the settled global config and the global collection exists before any index build), then the engine index build and the prune **after** it. Every writer of the shared index — memory registration, the engine module's init and reset, and the reindex tool — takes one lock via `_devbot_lock_memory_index` (`${XDG_CACHE_HOME:-~/.cache}/devbot/reindex-memories.lock`), and the index build happens once for the whole run. Two consequences worth stating: worker output goes to `storage/.init-all/NN.log` because interleaved headers are unreadable, and the registry lock must be keyed by the config's canonical path, not `DEV_BOT_ROOT`, or `DEV_BOT_GLOBAL_CONFIG` pointing elsewhere reopens the lost-update race. Reaping waits in launch order (bash 3.2 has no `wait -n`), which is not work-conserving — accepted, documented, and cheap to revisit if a head-of-list straggler ever dominates.
