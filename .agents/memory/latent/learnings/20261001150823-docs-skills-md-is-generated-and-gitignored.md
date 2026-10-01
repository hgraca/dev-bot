---
date: 2026-10-01
keywords: ["docs", "skills.md", "gather-module-docs", "generated"]
---

# docs/skills.md is generated and gitignored — regenerate, never hand-edit

`docs/skills.md`, `docs/agents.md`, `docs/commands.md`, `docs/hooks.md`, `docs/mcps.md` and
`docs/module-reference.md` are **aggregate pages produced by
`src/agentic/docs/tools/gather-module-docs.py`** (`make docs-gather`) and are **gitignored**
(`.gitignore:18`). Per-item purposes are derived from each module's own files — a `SKILL.md`
frontmatter `description`, an agent/command's front matter, a tool's `# description:` header — so
editing a `SKILL.md` description is enough: run `make docs-gather` and the table row updates itself.
Do **not** hand-edit `docs/skills.md`, and do not `git add` it — neither the file nor a row edit
belongs in a commit.

This supersedes the older instruction to update the `docs/skills.md` row by hand after changing a
skill description; that held before the module-docs generator landed.
