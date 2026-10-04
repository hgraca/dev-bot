---
date: 2026-10-04
keywords: ["devbot", "audit", "probe", "parallel"]
aliases: ["probe namespace collision", "devbot-audit-probe cleanup", "audit thinking dir"]
---

# Audit probes must be scoped to the run's report number

## Context

The e2e launchers (`tests/test-project/test-{oc,cc}.sh`) bind-mount the fixture's `thinking/`
dir into the container, so parallel cc/oc audits write into the same directory. The report id is
already collision-safe — `reserve_audit_nn` (test-lib.sh) claims it under `noclobber` and passes
it as `DEVBOT_AUDIT_NN` — but the probe/scratch files were not.

## Trap and fix

The cleanup step swept a bare `devbot-audit-probe-*` glob, so one audit's final cleanup deleted a
sibling audit's **in-flight** probes (audit-82 N5). Fixed in `b8f2b140`: probes are named
`devbot-audit-probe-<NN>-*` and the cleanup glob is scoped to the run's own `<NN>` (the report
number — `DEVBOT_AUDIT_NN` when the fixture sets it, else the next integer).

## Rule

Any scratch file an audit writes into the shared `thinking/` dir must carry the run's report
number in its name; never clean up with a bare prefix glob across parallel runs.
