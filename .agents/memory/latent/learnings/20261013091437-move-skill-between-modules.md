---
date: 2026-10-13
keywords: ["devbot", "skill-move", "docs-manifest", "skill-farm"]
---

# Relocating a skill between agentic modules: what to change, and why no re-init

Moving a skill from one `src/agentic/<module>/skills/` to another is a `refactor` that touches exactly four things:

1. **`git mv`**, not delete + add — `git mv src/agentic/<from>/skills/<skill> src/agentic/<to>/skills/<new-name>` so history is preserved and git reports it as a rename (`R099`).
2. **The moved `SKILL.md`** — frontmatter `name: devbot:<new-name>` and the `# <new-name>` body heading. The frontmatter name must equal `devbot:<directory-name>`.
3. **Both `docs.md` capability manifests** — the `skills:` flow-list entry (drop from the old module, add to the new), plus that module's `description` and per-capability prose bullet wherever they advertised the skill. The generated site is driven entirely by these manifests.
4. **Nothing else.** The `.agents/skills/devbot/*` farm symlinks point at the **module skills directory** (`_link_skills`), so both existing links (`…/docs → src/agentic/docs/skills`, `…/github → src/agentic/github/skills`) surface the moved folder immediately — an intra-\`agentic\` move needs **no** `devbot init`/`reinit`.

Verification is manual because the manifest↔on-disk consistency test is scoped to the `memory` module only: run `make docs-gather` and confirm the skill surfaces under the new module and is absent from the old (`docs/_data/modules.yml`, `docs/skills.md`). Generated docs are gitignored — regenerate, never hand-edit.
