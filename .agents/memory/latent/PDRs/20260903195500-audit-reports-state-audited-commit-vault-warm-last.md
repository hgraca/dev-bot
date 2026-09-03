---
date: 2026-09-03
keywords: ["devbot", "audit", "report", "commit"]
---

## Audit reports must state the audited commit; vault-warmth checks run last with retry

Stakeholder rule (2026-09-03, after audits 38–41): the `devbot:audit` report
header must include the DEVBOT REVISION (audited commit) of the dev-bot
install being audited, because audits 38–41 omitted it and their FAILs turned
out to describe pre-fix code from an older fixture baseline — without the
revision a reader cannot attribute findings to a code state. Second rule: the
project memory vault starts cold (0 files / "updated never") on a fresh reinit
or a direct harness launch and takes minutes to warm, so audit checks that
depend on vault warmth run as the LAST capability checks and retry once after
an explicit `reindex-memories`/`qmd update` before a cold collection is
recorded as a FAIL. Both rules are encoded in
`src/tools/devbot-cli/commands/audit.md` (header block §Report + §5 Memory
cold-start protocol).
