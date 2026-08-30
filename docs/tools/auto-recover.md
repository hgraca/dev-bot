---
layout: page
title: Auto-Recover
description: Automatic recovery from transient provider errors and silently-stalled subagents.
nav_section: docs
---

Detects transient LLM provider errors (rate limits, connection resets, upstream 5xx) and injects silent recovery prompts — keeping sessions alive without user intervention. A companion watchdog aborts subagent sessions whose provider stream stalls silently, which error-based recovery alone cannot catch.

## What it handles

- `MidStreamFallbackError`
- `APIConnectionError`
- `ECONNRESET` / `ETIMEDOUT` / socket hang up
- 503 / 502 / 504 upstream errors
- Silent generation stalls in subagent sessions (no error event raised)

## How it works

Both hooks live in the auto-recover module (`src/agentic/auto-recover/hooks/`) and are declared in its `hooks.json` manifest, loaded by the generic `on-hooks` adapter:

- `on-session_error-auto-recover.ts` — fires on provider errors and injects a recovery prompt with exponential backoff (5s → 10s → 20s). A lock file prevents concurrent recovery storms.
- `on-watchdog-silent-stall.ts` — polls subagent sessions and aborts any that stay busy without activity past a timeout.

## Error-based recovery

The `session.error` hook fires on provider errors. Auto-recover injects a recovery prompt with exponential backoff (5s → 10s → 20s). A lock file prevents concurrent recovery storms.

## Silent-stall watchdog

Provider streams can hang without raising an error event (observed with `cortecs/kimi-k3` — a vision generation emitted nothing for 4+ minutes). Since auto-recover only fires on `session.error`, such hangs were never recovered. The watchdog closes that gap:

- Every 30s it lists subagent sessions (those with a `parentID`) and checks their status.
- A session that is `busy` with no activity for 3 minutes is a stall candidate — but only if its last message is an in-flight assistant message with no pending or running tool call. A subagent waiting on a long tool (e.g. `npm install`, `docker pull`) is legitimately busy and is never aborted; a finished session is `idle` and skipped outright.
- **Two-strike design:** the first stale sample is logged; the session is aborted only if it is still stale on a later check, so a slow-but-streaming subagent is never killed on a single sample.
- On abort, the parent's `task` tool fails, so the orchestrator can retry or escalate.

Configure via environment variables:

| Variable                   | Default  | Meaning                                                |
| -------------------------- | -------- | ------------------------------------------------------ |
| `DEV_BOT_STALL_TIMEOUT_MS` | `180000` | Busy-without-activity window before a stall is flagged |
| `DEV_BOT_STALL_CHECK_MS`   | `30000`  | Poll interval                                          |

## Provider timeouts

`opencode.jsonc` sets request timeouts for the `cortecs` provider so a hung stream surfaces as an error and flows into error-based recovery instead of hanging forever:

| Option          | Value    | Meaning                                          |
| --------------- | -------- | ------------------------------------------------ |
| `timeout`       | `300000` | Full-request ceiling                             |
| `headerTimeout` | `60000`  | Time to first response headers                   |
| `chunkTimeout`  | `90000`  | No SSE chunk within the window aborts the stream |

`chunkTimeout` is the key guard for the silent-stall case: a stream that stops emitting mid-generation is aborted, which raises the error that auto-recover handles.

## Configuration

```jsonc
{
    "auto_recover": {
        "max_attempts": 5,
    },
}
```

After the ceiling is hit, the error surfaces to the user.

## See also

- [Configuration](/configuration) — full devbot.jsonc reference
- [Hooks](/hooks) — hook manifests and the `plugin:` hook pattern
