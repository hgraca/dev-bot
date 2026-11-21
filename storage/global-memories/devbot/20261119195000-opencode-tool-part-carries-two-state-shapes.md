---
date: 2026-11-19
keywords: ["opencode", "plugin-hook", "tool-parts", "session-idle", "agent-communication"]
aliases: ["tool part state is a string", "how a hook reads tool calls", "wait evidence"]
trigger-on: ["opencode-hook", "agent-communication"]
---

## An opencode tool part carries two state shapes, and the fixtures are the reference

A message's parts are the only place a hook can see what an agent actually did. The authoritative shape lives in this repo's own fixtures (`src/harnesses/opencode/tests/stats_tests.bats`, `opencode-v2`): `{"type": "tool", "tool": "bash", "state": {"status": "completed", "input": {...}}}` — tool name at `part.tool`, args at `part.state.input`, status at `part.state.status`. But `src/agentic/auto-recover/hooks/opencode/on-watchdog-silent-stall.ts` compares `part.state === "pending"` as a bare string, and `on-session-idle-validate.test.ts` fixtures use the same string form, so both appear in-tree. Read `state` defensively: `typeof p.state === "string" ? p.state : p.state?.status`, and args from `p.state?.input ?? p.input`.

Two consequences for anything that inspects messages from a plugin hook: a backgrounded `bash` returns immediately, so its part is `completed` (not `running`) while the work continues; and `client.session.messages({path:{id}})` is the only source — the plugin API exposes no shell registry, so a hook can prove a wait _started_ but never that its process is still alive. Keep such a check opt-in (a flag the hook passes) and fail soft: the idle hook only warns, so a wrong reading of the shape becomes log noise rather than a blocked agent.
