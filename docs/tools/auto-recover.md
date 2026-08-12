---
layout: page
title: Auto-Recover
description: Automatic recovery from transient provider errors.
nav_section: docs
---

Detects transient LLM provider errors (rate limits, connection resets, upstream 5xx) and injects silent recovery prompts — keeping sessions alive without user intervention.

## What it handles

- `MidStreamFallbackError`
- `APIConnectionError`
- `ECONNRESET` / `ETIMEDOUT` / socket hang up
- 503 / 502 / 504 upstream errors

## How it works

The `on-session_error` hook fires on provider errors. Auto-recover injects a recovery prompt with exponential backoff (5s → 10s → 20s). A lock file prevents concurrent recovery storms.

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
