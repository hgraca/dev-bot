---
date: 2026-09-29
keywords: ["devbot", "glob", "gitignore"]
trigger-on: ["verifying-subagent-deliverable"]
---

## The `glob` tool returns nothing for gitignored paths — use `ls`/`find` there

`glob` does not see files under gitignored directories, so it answers "No files found" for paths that plainly exist — for example `.agents/memory/work/active/<issue>/`, which is gitignored by design. That is a false *negative*, not an empty directory, and it very nearly produced a wrong "the subagent never wrote its report" verdict on a real 18 KB review artefact until `ls -la` showed the file. When verifying a deliverable under `work/`, `thinking/`, `latent/global/`, or any other ignored tree, use the `bash` tool with `ls`/`find`, and treat a glob miss there as inconclusive rather than as evidence of absence.
