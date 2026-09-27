---
date: 2026-09-27
keywords: ["devbot", "audit", "external-modules", "documentation-drift"]
---

# An audit command's checklist can drift from its ADR and cause false-positive FAILs

`src/tools/devbot-cli/commands/audit.md` §9 still told auditors that "a module declared by a disabled umbrella is skipped entirely — not cloned, mirrored, or wired ... any mirror it left is pruned on reinit" and that `devbot module list` "correctly renders ✖" for such a module. That was the model *before* ADR `20260927172101-external-modules-enablement-independent` (provisioning is enablement-independent: the global config, `vendor/` clones and storage mirrors are always provisioned; only the per-project `.agents/` wiring is gated). Because the checklist is the auditors' spec, `devbot-audit-71` (N4) and `devbot-audit-72` (§9) both reported the intended behaviour as a FAIL — audit-72 even called it a "regression" against audit-70's earlier ✖. The code was correct; the checklist was stale, and `external-modules/init.sh` carried a matching stale comment claiming a mirror prune that no code path performs.

Lesson: when an ADR changes a design that an audit checklist describes, the checklist is part of the change — reconcile it in the same session, or the next audits manufacture false FAILs. The audit command's external-modules section now carries the ADR citation.
