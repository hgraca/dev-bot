---
date: 2026-09-13
keywords: ["agents", "guards", "configuration-rules", "circumvention"]
---

## Universal agent rule: never circumvent an explicit configuration rule

The human stakeholder mandated a third universal MUST NOT rule for every agent
spec: an agent must **never circumvent an explicit configuration rule** — a
guard rule, a path or permission restriction in a harness config
(`opencode.json`, `.claude`), a hook block, or any other deliberate constraint.
Even when a technical workaround exists (another tool, a script, an alternate
path, a lower-level command), the agent must not route around the rule or
defeat its core intent. If a rule blocks the task, the agent stops, surfaces
the block to the user, and asks — it does not work around it.

The rule lives in the `MUST NOT` section of all 12 agent specs under
`src/agentic/devbot/agents/` and `src/agentic/devteam/agents/`, added as the
third universal bullet after the credentials and production/staging rules
(PDR `20260821225210-universal-agent-safety-rules`). Rationale: a guard exists
to encode intent; finding a loophole that satisfies the rule's letter while
defeating its intent is a safety violation, not cleverness.
