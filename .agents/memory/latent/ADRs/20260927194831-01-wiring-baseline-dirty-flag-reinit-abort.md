---
date: 2026-09-27
keywords: ["devbot", "reinit", "wiring-baseline", "auto-reinit", "dirty-flag"]
see: ["PDRs/20260927194831-01-reinit-failure-aborts-the-start.md"]
---

## The wiring baseline is a dirty flag, and a failed auto-reinit aborts the start

`.devbot.project.sha` (the per-project combined hash of the global + project configs) is now a **dirty flag**: `init`/`reinit` clear it *before* touching the tree — `bin/reinit.sh::_reinit_project` clears it before the reset scripts (a kill during a reset never reaches `init.sh`), `bin/init.sh` clears it at the top of `main` — and `init.sh` restores it at step 8b only on completion. A missing baseline already means "changed" (`_devbot_config_changed`), so an interrupted reinit leaves it missing and the next bare `devbot` start re-detects the change and repairs the tree. `bin/up.sh::_rebuild_external_module_config` refreshes the baseline after its global-config rewrite **only when it was clean before the merge** (it captures `_devbot_config_changed` before merging), so a standalone `devbot up`/`make up` can never consume a pending reinit. `_devbot_auto_reinit_if_config_changed` aborts the start on any reinit failure (`return 1`; `cmd_harness` `_fatal` + `exit 1`) — the non-interactive "continue anyway" escape and the interactive y/N override are gone; `bin/reinit.sh` propagates an `init.sh` failure (non-zero exit, skipping the ✔ banner) so the abort actually fires. Rationale: continuing on half-built wiring both launches the harness on a broken tree and, because a failed reinit never restores the baseline, re-runs the same failing reinit on every later start — a loop. Chosen over a stage-and-swap reinit redesign: the dirty flag makes recovery explicit and self-healing at a fraction of the change.
