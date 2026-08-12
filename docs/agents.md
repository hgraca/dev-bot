---
layout: page
title: Agents
description: Agent instruction files for the multi-agent orchestration system. Compatible with both opencode and claudecode.
nav_section: docs
---

DevBot ships **12 agents** across two modules: **2 primary agents** (invoked directly) and **10 subagents** (delegated to by a primary agent).

## Primary agents

Start here. Pick the experience that fits your workflow.

| Agent                                                           | Location                      | Description                                                                                                                                                                                                           |
|-----------------------------------------------------------------|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **`devbot`** <span class="badge-recommended">Recommended</span> | `src/agentic/devbot/agents/`  | **Pair programming partner.** Works alongside you incrementally — suggests, doesn't decide. Primes context at session start, recalls past decisions, loads the right tech skills. <em>Never autonomous — you're the driver.</em> |
| **`teamlead`** <span class="badge-power">Power User</span>      | `src/agentic/devteam/agents/` | **Full-delegation orchestrator.** Classifies work, routes to specialists, leads planning and implementation workflows, makes product decisions. <em>For the full multi-agent experience.</em>                          |

## Subagents

Primary agents delegate to these 10 subagents.

### DevBot module

| Agent          | Location                     | Description                                                                                                                |
|----------------|------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| **`expert`**   | `src/agentic/devbot/agents/` | **Consultant subagent.** Deep technical problem analysis on a higher-grade LLM. Proposes options; never implements.        |
| **`designer`** | `src/agentic/devbot/agents/` | **Design subagent.** Designs UX flows, interaction specs, screen designs, and visual acceptance criteria. Never writes code. |

### DevTeam module

| Agent           | Location                      | Description                                                                                                                       |
|-----------------|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| **`architect`** | `src/agentic/devteam/agents/` | **Software Architect.** Designs technical plans and ADRs. Does not write production code.                                         |
| **`critic`**    | `src/agentic/devteam/agents/` | **Critic.** Evaluates plans and audits the codebase for inconsistencies, architectural erosion, and pattern drift.                |
| **`developer`** | `src/agentic/devteam/agents/` | **Developer.** Implements the architect's plan into production code, following plans precisely.                                   |
| **`po`**        | `src/agentic/devteam/agents/` | **Product Owner.** Product domain expert; owns backlog grooming and answers business/requirements questions.                      |
| **`reviewer`**  | `src/agentic/devteam/agents/` | **Reviewer.** Reviews changes against the combined backlog and project conventions; reports issues without modifying code.         |
| **`scout`**     | `src/agentic/devteam/agents/` | **Scout.** Collects context for the orchestrator at session start. Does not delegate.                                             |
| **`security`**  | `src/agentic/devteam/agents/` | **Security Engineer.** Security audits, threat modelling, vulnerability assessment, and secure code review without modifying code. |
| **`tester`**    | `src/agentic/devteam/agents/` | **Tester.** Validates implementations against requirements; writes and executes automated tests.                                   |

## Structure

The directory layout behind the tables above:

```
src/agentic/devbot/agents/
├── devbot.md        — DevBot (pair programming partner, primary)
├── expert.md        — Expert (consultant subagent)
└── designer.md      — Designer (design subagent)

src/agentic/devteam/agents/
├── teamlead.md      — TeamLead (orchestrator, primary)
├── architect.md     — Software Architect
├── critic.md        — Critic
├── developer.md     — Developer
├── po.md            — Product Owner
├── reviewer.md      — Reviewer
├── scout.md         — Scout
├── security.md      — Security Engineer
└── tester.md        — Tester
```
