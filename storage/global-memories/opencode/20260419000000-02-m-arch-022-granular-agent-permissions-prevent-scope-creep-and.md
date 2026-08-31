---
date: 2026-04-19
keywords: ["opencode"]
---

## M-ARCH-022: Granular agent permissions prevent scope creep and accidents

Implementing bash permission restrictions per agent role
Restrict each agent to only the commands needed for their role - Reviewer gets git diff/log/show only, Tester gets test runners only, Developer gets safety rails on destructive commands. Use opencode's glob pattern support for fine-grained control
