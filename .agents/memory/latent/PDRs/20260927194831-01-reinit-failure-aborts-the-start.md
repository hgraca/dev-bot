---
date: 2026-09-27
keywords: ["devbot", "reinit", "start-abort", "failure-policy"]
see: ["ADRs/20260927194831-01-wiring-baseline-dirty-flag-reinit-abort.md"]
---

## A devbot-triggered reinit that fails must abort the start

Stakeholder rule (2026-09-27): when the automatic reinit a bare `devbot` start runs does not finish correctly, the start must exit with an error rather than continue — otherwise the harness launches on half-built wiring and, since the failed reinit never restores the baseline, every subsequent start re-detects the change and fails again: an unbounded reinit loop. This removes the former non-interactive "continuing the start anyway" escape (and the interactive y/N override) — the recovery path is now always `devbot reinit` run manually. Corollary: an *interrupted* (killed) reinit must leave the wiring flagged for repair, so the next start heals it automatically instead of running on a broken tree.
