---
date: 2026-05-11
keywords: ["otel", "otlp"]
---

## Plan vs. orchestrator prompt: when they conflict, ask BEFORE expanding OR shrinking scope

The Task 5 plan (PLAN-task-05-…ARCH-2026-05-07-001.md) §Step-2 specified "gateway Deployment + ConfigMap + LoadBalancer Service" as a single atomic deliverable; §Step-3 specified ingress rename + host change. The orchestrator's PR-1 prompt mixed these signals: it told the agent to follow Steps 1–4 but listed `ingress-otlp.yaml` (the Service file) and the rename together in the "out of scope" section. Commit history: `ff6f769` followed the plan and included everything (scope creep); `83ae671` reverted both groups together (scope undershoot — removed Service alongside rename, leaving an unreachable gateway Deployment); `b3a8818` re-added only the Service. The prompt's exclusion list was internally inconsistent with the plan's atomic-deliverable boundaries — neither agent invocation caught it. **The correct move when plan and prompt disagree is to STOP and signal `[NEEDS_INPUT]!` citing the specific conflict — works both ways (whether the prompt is broader OR narrower than the plan).**
Fix: At the start of any delegation that references a plan, diff plan-scope vs. prompt-scope. If they differ, signal `[NEEDS_INPUT]!` with both quotes before writing any file. Also: when reverting "scope creep", verify each reverted file individually against the plan's atomic-deliverable boundaries — a single revert can cross multiple Step boundaries. See [[ADRs]], [[PDRs]].
