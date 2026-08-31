---
date: 2026-05-07
keywords: ["opencode", "plugin"]
---

## M-FLOW-074: Gotcha-to-skill graduation — promote a captured trap into a skill rule once it pays off across delegations

agent-communication iteration captured three trap-style entries during work: gotcha L1037 (developer false-[FINISHED] → trust-calibration prompt formula), gotcha L1057 (uniform-default-arguments hide multi-arity bugs), gotcha L1062 (plugin tests pollute real vault when they pass real paths as `directory`). After the implementation retrospective surfaced them as follow-ups, the address-retro loop promoted all three to permanent skill rules: trust-calibration formula → `.opencode/skills/devbot/workflow/agent-communication/SKILL.md` §Delegation Format, multi-arity rule → `.opencode/skills/devbot/dev/make-tests/SKILL.md` MUST, tmpdir-isolation rule → same skill MUST NOT. The original gotchas remain as long-form context; the skills carry the actionable directive that flows into agent prompts.
A gotcha is the right home for the FIRST occurrence of a trap (full context, recovery technique, specific symptoms). A skill rule is the right home once the workaround has been validated across at least two distinct uses AND the rule is short enough to live as one bullet. The retrospective → address-retro loop is the graduation mechanism: retros surface "this paid off, codify it"; address-retro debates per-suggestion approval and lands the diff. Do not pre-graduate to skills (rules without context fail to convince). Do not leave validated workarounds languishing as gotchas (agents won't load `gotchas.md` mid-task; they load skills). The dev/make-tests MUST/MUST NOT bullets and the agent-communication subsection are now tight enough to be quoted into delegation prompts directly.

- See also: [[gotchas]] L1037, L1057, L1062; `.opencode/skills/devbot/workflow/agent-communication/SKILL.md` (Trust-calibration prompt subsection); `.opencode/skills/devbot/dev/make-tests/SKILL.md` (MUST: parameter coverage; MUST NOT: real project paths as test args).
