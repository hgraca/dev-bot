---
date: 2026-09-18
keywords: ["grade-tools", "tool-usage", "csv", "self-improvement", "finish-flow"]
see: ["global/opencode/20260918122005-01-opencode-shell-env-exports-session-id-to-bash.md"]
---

## Grade every tool used in a session into tools-grades.csv at the finish flow

After `devbot:remember-session`, the primary agent runs `devbot:grade-tools`: it grades every MCP
server and skill used in the session slice from 0 (not used) to 5 (critical — the task was very
likely impossible without it) and appends one row to `.agents/logs/tools-grades.csv`, to inform which
tools to keep, remove, substitute, or improve. Stakeholder decisions (2026-09-18): one column per
MCP server, except the self-owned `devbot-tools` which is one column per tool (so our own tools can be
pruned or improved); then one column per skill; a `notes` column directly after the date carries the
signal behind a grade (which substitute existed for a 3, whether a poor result was a tool limitation
or a configuration/usage issue); row ids are `<session-id>-NN` per session starting at 01; a tool used
for the first time becomes a new column and earlier rows backfill 0; each run grades only the work
since the previous row in this session, not the whole session. A bundled `record-grades.py` owns the
file — canonical column order (MCP before skills), quoting, an exclusive lock, and an atomic
mode-preserving write — while the agent supplies judgement only. Built-in tools (bash, edit, read,
grep, task, …) are out of scope.
