---
date: 2026-09-14
keywords: ["devbot", "gpu_enabled", "up.sh", "session-teardown"]
---

# Diagnosing a devbot start failure: two misleading signals

When `devbot` refuses to start, the output points the wrong way twice. Both were hit while fixing the macOS start failure of 2026-09-14.

## `gpu_enabled` never self-heals

`_devbot_detect_gpu` runs only from `bin/install.sh` and `bin/update.sh`, and `update.sh` `exit 0`s early when the checkout is already on the newest release (its `at`/`ahead` cases come before the detection call). A bare `devbot` start on an up-to-date install therefore never re-evaluates the flag: a value recorded wrongly — e.g. the no-docker-daemon branch storing the HOST GPU probe (`_has_gpu`) on an Apple Silicon Mac, where container passthrough is never available — persists indefinitely. Any fix must either require a live capability probe at the point of use or run detection somewhere it can self-correct; note that writing the config on every start would change the config hash and force a reinit each time.

## A failed start reports the session teardown, not the failure

`cmd_harness` registers a session and traps `INT TERM EXIT`; when `up.sh` fails it exits through that trap, so the output ends with "Last devbot session ended — removing devbot containers". That line reads as the CAUSE of the failure although it is its consequence, and it hides the fact that the harness was never reached. It is now flagged (`_DEVBOT_START_FAILED`) and kept quiet. When debugging a start, look for the absent success markers instead — a missing "✔ Docker services started" or harness banner — rather than trusting the last line printed.
