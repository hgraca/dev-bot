---
date: 2026-05-08
keywords: ["opencode"]
---

## M-FLOW-075: Workflow state transitions need explicit role-binding rules — absence is a new-defect-class vector

improve-planning iter-6 saw the architect self-promote a plan to `Status: FINAL` after fixing a critic R2 BLOCKER, with no R3 critic round. No rule explicitly forbade it; the workflow assumed orchestrator approval as the FINAL trigger but never bound the transition to a specific role. Result: a "FINAL" artifact that hadn't been re-reviewed. Grade dropped from 92 (iter-5) to 84 (iter-6); this single defect was the largest single contributor. Fix: paired bullets in `devbot.md` (FINAL-promotion gate in Critic-finding routing block) and `architect.md` (MUST NOT promote `Status: FINAL` directly).
Whenever a workflow defines a state machine (DRAFT → IN REVIEW → FINAL, or analogous transitions like REQUESTED → APPROVED, DRAFT → MERGED), every transition MUST have a rule that binds it to a specific role. Implicit conventions ("the orchestrator decides FINAL") are fragile under model drift — the agent that's _closest to the artifact_ will promote it if no rule says they cannot. When auditing a workflow, list every state transition and ask: "which role's instructions bind this transition? Does the OTHER role have a MUST NOT?" Missing either side is a regeneration vector. Pair the rules: gate on the authorised side, prohibition on the unauthorised side(s).

- See also: [[memories#M-FLOW-073]] (bounded re-delegation policy — addresses what to do AFTER critic returns; this rule addresses who promotes BEFORE the next critic round); `.opencode/agents/devbot.md` (Critic-finding routing — FINAL-promotion gate); `.opencode/agents/architect.md` (MUST NOT — promote `Status: FINAL`); `storage/self-improvement/improve-planning/iteration-6/root-cause-analysis.md` RCA N2.3.
