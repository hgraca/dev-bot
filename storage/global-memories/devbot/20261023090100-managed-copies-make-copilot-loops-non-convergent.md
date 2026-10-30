---
date: 2026-10-23
keywords: ["devbot", "dev-tools", "copilot", "review-loop", "managed-files"]
aliases: ["copilot never converges", "resolveReviewThread", "plugin-copied files in PR diff"]
---

## Copilot loops never converge when consumers commit plugin-managed files

Consumers of `get-e/dev-tools` commit the plugin-copied tree (`scripts/**`, root `Makefile`). A dev-tools bump therefore puts ~50 generated files into each consumer PR's diff, and Copilot reviews them as new code — re-reporting items whose lines it has not seen change, and surfacing one fresh edge case per pass. Ten-plus review rounds on a single helper is the observed outcome.

Two practices make this survivable: fix shared findings in dev-tools and re-sync (never patch the copies in a consumer PR), and treat the loop as converged when Copilot reports "No open issues" while the only remaining note targets a degraded/fallback path. Threads do not auto-resolve; mark them with the GraphQL mutation `resolveReviewThread(threadId:)` after listing unresolved threads via `reviewThreads(first: 100) { nodes { id isResolved } }`.
