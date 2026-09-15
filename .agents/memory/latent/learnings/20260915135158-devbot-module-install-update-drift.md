---
date: 2026-09-15
keywords: ["devbot", "module", "install", "update", "lifecycle"]
---

# dev-bot module lifecycle: duplicated logic between install.sh and update.sh drifts

## The trap

A dev-bot module's `install.sh` and `update.sh` are separate entry points that historically carried **duplicated** logic (download the binary, install the skills). When a change is swept through one of them — e.g. removing a helper function from `functions.sh` and deleting its use from `install.sh` — the sweep is easy to stop halfway: the definition is gone, the other caller remains.

This is exactly how a BLOCKER shipped: `_signoz_archive_name` was removed from `functions.sh` and its use removed from `install.sh`, but `update.sh` still called it under `set -euo pipefail`. Result: `command not found`, exit 127, on every `devbot update` for any adopter with that module enabled. `make test` stayed green because nothing executed `update.sh`.

## The rules

- **Put shared logic in `functions.sh`, not in both scripts.** Extract the common step as a `_<module>_<verb>` helper and have `install.sh` and `update.sh` both call it. Duplication is what allowed the drift.
- **When deleting a helper, grep for its CALLERS, not just its definition.** The definition living in `functions.sh` while callers live in per-script files is what makes a half-sweep invisible.
- **Give every lifecycle script an executing test.** File-existence assertions (`[ -f update.sh ]`) cannot catch a script that exits 127.
- **`init.sh` runs on `devbot init`/`reinit`; `update.sh` only on `devbot update`.** A module whose engine is a globally-installed CLI needs a dependency self-heal in `init.sh`, because reinit does not run `update.sh`.

Verified-by: review of the T3.3 shared-gateway changeset (finding F1), fixed in commit `431e3f1a`.
