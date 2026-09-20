---
date: 2026-09-20
keywords: ["devbot", "audit", "audit-fix", "stale-report", "verify"]
---

# On `devbot:audit-fix`, verify every report finding against HEAD before fixing

The audit reports under `tests/test-project/.agents/memory/thinking/devbot-audit-NN.md` are gitignored snapshot artifacts: each names an audited commit (e.g. `e611961`, a release checkout) that is usually NOT an ancestor of the working branch, because dev-bot is installed from releases while the branch carries newer work — so `git merge-base --is-ancestor <audited> HEAD` returning NO is expected, not a red flag, and a report can flag something already fixed.

Procedure that worked (audits 61/62): grep the reports for `NOTE`/`FAIL`, then verify each against the current tree (file content, `git log -S`, the existing tests) instead of trusting the report; search memory for a prior fix-session note recorded right after that audit — `search-memories` surfaced `20260911221434-audit-61-62-fix-session.md`, which listed what was already fixed and which findings were false positives. Only genuinely open items were implemented (a stale vendored graphify skill, a false documentation claim); the rest were verified-resolved and left untouched. Do not re-fix a finding that HEAD already satisfies.
