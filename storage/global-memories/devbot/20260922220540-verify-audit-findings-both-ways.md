---
date: 2026-09-22
keywords: ["devbot", "audit", "verification", "review"]
trigger-on: ["devbot-audit-findings", "verify-audit-suggestion-before-implementing"]
---

## An audit report is evidence, not truth — verify each finding in both directions

Working `no-vcs/devbot-audit-01.md`, two of its twelve findings did not survive contact with the code. FAIL-2 suggested documenting the macOS host-networking limitation in `src/agentic/datasources/compose.tpl.yml`, which had carried that exact comment since `a57bee91b` — four days *before* the audit ran — so the proposed fix was already in place. And §10 concluded "chrome-devtools has no container" correctly, yet walked past the consequence: because the launcher passed neither `--isolated` nor `--userDataDir`, the stdio server's default shared Chromium profile meant a second concurrent instance's browser could not start at all. The same trap applied to the reviewer: it cited `jq -e 'index(…)'` as the repo idiom when `functions.sh` actually used `grep -q '"memory"'`.

So before implementing an audit or review suggestion, grep for the fix — it may already be there, in which case the finding is a false positive to record rather than work to do. And treat "no defect found in subsystem X" as unproven rather than verified: say which check was run and what it would have missed. A finding is a pointer to where to look, not a work order; the audit's own severity labels carry no confirmation that the underlying claim is accurate.
