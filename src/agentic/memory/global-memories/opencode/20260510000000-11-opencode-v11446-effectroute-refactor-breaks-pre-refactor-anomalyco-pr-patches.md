---
date: 2026-05-10
keywords: ["opencode", "plugin", "session"]
---

## opencode v1.14.46+ Effect/route refactor breaks pre-refactor anomalyco PR patches

Anomalyco's opencode upstream refactored after PR #18559 was authored. `packages/opencode/src/server/routes/session.ts` was deleted (handlers moved to `server/routes/instance/httpapi/handlers/session.ts` with Effect-based `Effect.fn` shape and `yield* promptSvc.command(...)`); `session/prompt.ts` plugin trigger switched from `await Plugin.trigger(..., output)` to `yield* plugin.trigger(..., {parts})`. Patches like #18559 that touch these files cannot apply mechanically — `git apply --3way` reports `error: <path>: does not exist in index` for the deleted file AND fuzzy-matches the prompt.ts hunk against unrelated context (silent partial-apply risk). Failure mode: `.pr-N.err` shows `does not exist in index` at top, but follow-up lines say "Applied patch ... with conflicts" or "cleanly" for surviving files — the orchestrator may misread this as partial success. Verification: after apply, `git diff --cached --stat` shows only the unrelated PR's changes; the abandoned PR's signature keywords (e.g. `cancelled`, `output.cancelled`) are absent from the working tree. **Fix**: treat any `does not exist in index` as a hard structural-incompatibility signal — abandon the PR (with `// TODO: stale` + commented-out config entry per project rule); do not attempt manual port unless explicitly approved as a fresh feature implementation. Patching globally paused 2026-05-10 — see [[PDRs]]. PR #25724 (the prefill fix that did apply cleanly) is also paused for now.

---
