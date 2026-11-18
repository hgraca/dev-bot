---
date: 2026-11-18
keywords: ["devbot", "audit-fix", "audit", "design-intent"]
see: ["learnings/20260920120200-audit-fix-verify-against-head-before-fixing.md"]
---

# An audit's suggested fix can contradict the design — read the intent first

## Observation

Addressing audit-03's ten findings, two were **design properties**, not defects. The "missing v2 plugin SDK" was a documented trade-off (`_install_plugin_deps` installs only `bun-pty`; the 2.x host supplies `@opencode/plugin`), and "rendered sidecars not running" was the deliberate two-gate behaviour of ADR `20260930122947`. The audit's suggested fix for the latter — "start every rendered service" — would have resurrected the ~380 MiB-per-sidecar residency that ADR exists to prevent.

## Rule

Before implementing a suggested fix, find the code's stated intent — the function comment, the module page, the ADR — and let it override the report. The audit observes behaviour; the developer owns the reason. Address a by-design finding by making the behaviour self-explaining (a log line, a docs paragraph) or by recording "verified, no change" — never by changing the design to satisfy the report. The earlier rule still applies first: verify the finding against HEAD.
