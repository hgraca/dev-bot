---
date: 2026-11-17
keywords: ["session-usage", "context-window", "model-catalog", "devbot"]
---

# `session-usage` prints no percentage when the model is absent from the catalogue

## What it returns

`build_payload` (`src/_shared/session_usage.py`) resolves the limit through `model_limit.resolve(provider, model)`. When that returns nothing, `percent` is `null` and `render_text` prints `context <tokens> (limit unknown)` instead of `context <tokens> / <limit> (<pct>%)`. The JSON payload keeps `context_tokens` but nulls both `context_limit` and `percent`; `test_unknown_model_leaves_the_percentage_null` (`src/_shared/test_session_usage.py`) pins that behaviour as supported, not a failure.

## Why it matters for instructions

Any rule that tells an agent to "check the percentage" before deciding how much session it has must also say what an absent percentage means, or the agent is stuck with a MUST it cannot satisfy. The dev-bot session-budget rule resolves it by declaring `limit unknown` inconclusive: it never justifies an early stop.
