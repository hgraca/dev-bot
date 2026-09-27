---
date: 2026-09-27
keywords: ["devbot", "e2e", "audit-report", "docker-mount"]
---

# The audit report must reach the fixture while the run is live, and the id must be reserved

The e2e launchers (`tests/test-project/test-{oc,cc}.sh`) run their container
detached and then attach an interactive shell; the launcher process stays alive
until the human exits. `sync_run_outputs` copied the audit report back only at
launcher exit, so while a session was interactive the report sat at
`/tmp/devbot-test-<harness>.XXXX/.agents/memory/thinking/devbot-audit-01.md` and
had to be copied out by hand.

Fix (commit `9801ae0f`): bind-mount the fixture's `thinking/` dir at
`/app/.agents/memory/thinking`, so the audit writes `devbot-audit-<NN>.md`
straight onto the fixture. That makes the report id a resource parallel runs
share, so `reserve_audit_nn()` (test-lib.sh) claims it by creating an empty
`devbot-audit-<NN>.md` under `set -o noclobber` (lock-free — a racing run's claim
fails and it takes the next id), the launcher passes it as `DEVBOT_AUDIT_NN`, and
`audit.md` writes that placeholder in place. `sync_run_outputs` now only files
logs, under the reserved id.

Supersedes the "on exit the launcher syncs the run's audit report (next free NN
on the real tree)" sentence in
`20260902204416-oc-cc-harness-tests-test-project.md`.
