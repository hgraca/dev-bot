---
date: 2026-11-03
keywords: ["opencode", "deepseek", "provider", "retry", "latency"]
aliases: ["Service is too busy", "stream error", "provider stall"]
trigger-on: ["opencode-provider-retry", "opencode-performance"]
---

## A flaky provider shows up as "feels slow", not as an error the user sees

When opencode's configured model provider is overloaded, the symptom is multi-second stalls rather than a visible failure: `deepseek/deepseek-flash` returned `AI_APICallError: Service is too busy` 59 times in one log (31 in a 2-hour window), and each failure retried ~3 times over ~9 s before falling back to another provider — 71 of 93 errors were on `deepseek`. The config routed `model`, `small_model`, and most agents to that provider, so every subagent and title-generation call paid the retry cost. Diagnose by grepping `~/.local/share/opencode/log/opencode.log` for `stream error` and `too busy`, then count errors per `providerID`; fix by pointing the default/small/agent models at a provider that answers (here `cortecs/deepseek-v4.1-flash`).
