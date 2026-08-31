---
date: 2026-05-07
keywords: ["opencode", "plugin", "session", "tool"]
---

## Idle-driven plugin loop prevention — three-layer guard

When an opencode plugin reacts to `session.idle` and itself sends a synthetic prompt, that prompt triggers another `session.idle` after the agent responds — an infinite loop unless guarded. Use three independent layers, all worktree-scoped under `.ai/devbot/memory/thinking/`:

1. **Lock file with TTL** — `.<plugin>-lock-<worktreeSlug>` written on entry, checked on entry. Skips re-entry within window. Use 5–10 min TTL depending on the plugin's expected pacing. Stale-lock-NOT-deleted-on-detection: never delete a lock when finding it stale; only the writer deletes locks. Prevents two concurrent handlers fighting.
2. **Last-message tag check** — embed a unique tag in the synthetic prompt (e.g. `[DevBot-StatusEnforcer]`). On entry, scan the last user message; if it carries the tag, skip — the agent is currently responding to YOUR prompt, not a real human turn.
3. **Per-session attempt counter with persistence + GC** — `.<plugin>-counter-<worktreeSlug>.json` of `{ sessionId: { attempts, lastNudge } }`. Increment on send, reset on success-signal, prune entries older than 24h, evict oldest when over `MAX_ENTRIES` (default 100). Cap attempts (default 2) and emit a stderr line at ceiling so humans can see the giving-up event in plugin logs.

Exemplars: `src/plugins/remember-session.js` (lock + tag), `src/plugins/agent-communication.js` (lock + tag + counter, plus stall-flag coordination with remember-session). Cross-plugin coordination uses a fourth file (`.<plugin>-stall-<slug>.json`) read by the OTHER plugin to skip its own work while a stall is being addressed — TTL = lock-TTL + grace-window.

When to apply: any opencode plugin that sends synthetic prompts in response to events the agent's own response will re-trigger. Always combine all three layers — none is sufficient alone (lock alone fails on session restart, tag alone fails if the agent strips the tag, counter alone allows infinite-loop bursts within a single TTL window).

Cross-ref: [[gotchas]] L1057 (test isolation pitfalls when state lands in real vault), L1037 (developer trust calibration when self-reporting test results), [[ADRs]] M-ARCH-034 (duplicate constants between coordinating plugins, no cross-imports). Plugin docs: `docs/tools/agent-communication.md`, `docs/tools/remember-session.md`.
