---
date: 2026-05-07
keywords: ["opencode", "session"]
---

## Skill loader silently drops skills with malformed YAML frontmatter

A skill (`improve-planning`) failed to appear in any session's available-skills list despite the `SKILL.md` existing on disk. Restarting opencode did not fix it. Root cause: the `description:` field used a double-quoted YAML string containing **unescaped inner double quotes** (`description: "... user says "improve planning", "planning quality", ..."`). YAML terminates the string at the first inner `"`, producing a parse error. The opencode skill loader silently drops skills whose frontmatter fails to parse — no warning, no log entry, no diagnostic. The skill simply does not exist from the agent's perspective. See [[memories]] M-LSN-NNN for the diagnostic technique (yaml.safe_load over all `*.md` files under `.opencode/` and `src/`).
Fix: Use single-quoted YAML strings for descriptions containing double quotes (`description: 'user says "X", "Y"'`) — this is the convention already used by other skills in the repo (e.g. `optimize-instructions`). Backslash-escaping (`\"`) also works but is uglier. When a skill is reported missing, run a frontmatter parse sweep across all skill files before assuming a loader bug or restart problem.
