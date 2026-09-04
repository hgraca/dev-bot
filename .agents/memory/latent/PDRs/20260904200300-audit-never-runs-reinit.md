---
date: 2026-09-04
keywords: ["devbot", "audit", "reinit", "read-only", "mandate"]
---

## The dev-bot audit never runs `devbot reinit`

Stakeholder rule (2026-09-04): the `/devbot:audit` command must never run
`devbot reinit` — nor `devbot module add/remove` nor the destructive fixture
scripts (`test-reinit.sh`, `test-oc.sh`, `test-cc.sh`). Rationale: reinit
mutates the very tree under audit, can invalidate the running session's own
registries (audit-45 §3 — a mid-session reinit killed the Skill tool for the
rest of that session), and verifying a reinit by running one is
self-referential. Every probe that historically required reinit (the §1
byte-idempotency double-reinit, the §9 module add→reinit→remove loop) is
recorded as NOT-RUN in the report with its sanctioned vehicle: the fixture
launchers run `test-reinit.sh`'s double reinit in a disposable container and
print `BYTE-IDEMPOTENCY-PASS/FAIL`, and the module flow likewise belongs in a
disposable container. Implemented in
`src/tools/devbot-cli/commands/audit.md` (commit `818e5a51`) — the top-level
mandate previously said "no reinit" while §1/§9 still instructed the auditor
to run it, which split audits into read-only (48/49) and reinit-ing (47/50)
behaviors; the sections now agree with the mandate.
