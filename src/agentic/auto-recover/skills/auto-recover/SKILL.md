---
name: devbot:auto-recover
description: "Automatically recovers from transient provider errors (MidStreamFallbackError, APIConnectionError, ECONNRESET, etc.) by injecting a silent recovery prompt on session.error events. Use this skill whenever a session errors out, stalls, or disconnects mid-response."
---

# Auto-Recover

Detects mid-stream provider errors and automatically injects a recovery prompt so the agent resumes without user interaction. This is a passive event hook — it requires no manual invocation.

## When It Fires

| Situation                                                                    | Action                                       |
| ---------------------------------------------------------------------------- | -------------------------------------------- |
| Provider mid-stream error (MidStreamFallbackError, APIConnectionError, etc.) | **Auto-recover** injects recovery prompt     |
| Network timeout (ECONNRESET, ETIMEDOUT, socket hang up)                      | **Auto-recover** injects recovery prompt     |
| Upstream 503/502/504 error                                                   | **Auto-recover** injects recovery prompt     |
| Session exceeds max recovery attempts (default: 3)                           | Surfaces error to human — stops retrying     |
| Any non-transient error                                                      | Does nothing — leaves error visible to human |

## How It Works

1. Listens for `session.error` events
2. Checks if the error message matches known transient patterns
3. Acquires a worktree-scoped lock to prevent concurrent recovery storms
4. Manages a per-session attempt counter with TTL (30-min window)
5. Sends a synthetic hidden recovery prompt tagged `[DevBot-AutoRecover]`
6. Uses exponential backoff between retry attempts (5s, 10s, 20s, ...)
7. Releases lock after recovery completes

## Registration

### OpenCode

Registered in `opencode.jsonc` as a `session.error` event plugin. Fires automatically on any session error.

No manual configuration needed.

### Claude Code

Claude Code does not expose a `session.error` lifecycle event — auto-recovery is only available in OpenCode.

## Configuration

Optional: set `auto_recover.max_attempts` in `.devbot.project.jsonc` to override the default of 5:

```jsonc
{
    "auto_recover": {
        "max_attempts": 5,
    },
}
```

## Tunables (source)

| Parameter              | Default          | Description                                     |
| ---------------------- | ---------------- | ----------------------------------------------- |
| `LOCK_TTL_MS`          | 120000 (2 min)   | Lock file TTL — prevents recovery storms        |
| `COUNTER_TTL_MS`       | 1800000 (30 min) | Per-session attempt window                      |
| `DEFAULT_MAX_ATTEMPTS` | 5                | Max recovery attempts before surfacing to human |
| `COOLDOWN_BASE_MS`     | 5000 (5s)        | Exponential backoff base (doubles each attempt) |

## Source

- Logic: `src/agentic/auto-recover/tools/auto-recover.ts` (shared, harness-agnostic)
- OpenCode hook: `src/agentic/auto-recover/hooks/opencode/on-session_error-auto-recover.ts` (declared in the module `hooks.json` manifest, loaded by the `on-hooks` adapter)
- Claude Code hooks: `src/harnesses/claudecode/hooks/on-posttooluse-auto-recover.sh` + `on-stop-auto-recover.sh`
