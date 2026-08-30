---
date: 2026-08-21
keywords: ["devbot", "agent-rules", "container", "production-safety"]
---

## Universal agent safety rules: container execution and production/staging isolation

All 12 agent specs now carry two universal safety rules mandated by the stakeholder. First, when a project uses a container for development, every shell command must run inside the container (via `make` targets or `docker exec`), never on the host — this avoids host-side file-permission drift and keeps the agent constrained to the project environment. Second, an agent must never change a production or staging environment system unless explicitly asked to do so, and even then it must ask the user to confirm before proceeding. Rationale: container execution sandboxes agent actions and prevents permission issues; the production/staging rule prevents irreversible changes to shared environments without explicit human sign-off. These rules live in the `MUST` / `MUST NOT` sections of all 12 agent files under `src/agentic/devbot/agents/` and `src/agentic/devteam/agents/`.
