---
date: 2026-04-17
keywords: ["graphify", "graph"]
---

## M-ARCH-007: Per-project storage isolation prevents data corruption

All Graphify projects were sharing storage/graphify/ directory, causing overwrites when multiple projects initialized
Multi-tenant systems need isolated storage per tenant/project. Shared directories are a corruption risk.
