---
date: 2026-04-19
keywords: ["shell"]
---

## M-FLOW-043: Critic review catches specification conflicts before implementation

Critic agent reviewed Repomix integration plan and found 3 BLOCKER-level conflicts between backlog and architecture spec
Always run critic review on plans before implementation to catch conflicts between different planning documents. Critic found doctor.sh pattern mismatch, config location conflict, and skill path conflict that would have caused implementation issues
