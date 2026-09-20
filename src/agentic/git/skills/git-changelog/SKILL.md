---
name: devbot:git-changelog
description: "Write a release file (release notes / changelog) for a version from the branch's commits. Use whenever a new release or git tag is being created, or the user asks for 'release notes', 'a release file', 'the changelog', 'sum up what changed this release', or to update an existing release*.no-vcs.md — even if they do not say 'changelog'."
---

# Git Changelog (release file)

Produce a short, human-readable release file that summarises what changed in a
release. It is a changelog for a release/tag, **grouped by change** — not a
commit-by-commit log.

## Output contract

- **File name:** `release.v<MAJOR>-<MINOR>.no-vcs.md` at the repo root — the
  release version with dots turned into dashes, e.g. release `v1.5` →
  `release.v1-5.no-vcs.md`.
- **Heading:** `# Release v<MAJOR>.<MINOR>.<PATCH>` — the full three-part semver,
  e.g. `# Release v1.5.0`.
- **The `.no-vcs.md` suffix is load-bearing:** it matches the `*no-vcs*`
  gitignore rule, so the file is **never committed**. Never `git add` it, and
  never ask where it goes — a release file is a local artifact.
- Update an existing file in place; never create a second release file for the
  same version.

## Content rules

- One bullet per **user-facing change**, ordered by significance.
- **Group commits into changes:** one logical change may span many commits — a
  feature, its tests, its docs, its fixups collapse into a single bullet. Never
  emit one bullet per commit.
- Phrase each bullet at the level of **intent/decision**, not implementation
  ("Removed model downloads, embeddings and MCP from the QMD module", not
  "refactor(qmd): make the memory-search path BM25-only").
- **Omit internal churn** — test-only, fixup, and pure-docs commits that change
  nothing a user or downstream module sees. Mention docs/infra only when they
  change visible behaviour.
- **Cap every bullet line at 72 characters** — the whole line including the
  `- ` marker. Keep a bullet to a single line; a second line is allowed only
  when a decision needs one sentence of rationale, and it is capped at 72 too.
- Keep it tight — a handful of bullets.

## Procedure

1. Determine the release range — commits since the previous release/tag
   (`git log --oneline <last-tag>..HEAD`), or the branch's unique commits
   (`devbot:git-report` returns them).
2. Group the commits into logical changes.
3. Phrase each group as a product/decision statement.
4. Write or refresh `release.v<MAJOR>-<MINOR>.no-vcs.md`.
5. Do not commit it.

## Worked example — release v1.5

17 commits on the branch collapsed into 3 bullets.

**Commits, grouped:**

- qmd BM25-only: `976ce2fb` ADR, `b8987b2e` lifecycle, `5e4d0a19` ollama
  share, `5a53cff7` e2e, `53399d56` docs/skill
- qmd not agent-invokable: `797c8300` MCP removed, `1197f056` reserved manifest
  removed, `52e37fc7` devbot-tools, `90ec658f` guards, `7d86fcf8` tests, and
  the learning note
- Agent instructions hardened: `01a0cf15` plan confirmation, `b19a59de`
  no-circumvention (all 12 agents + PDR), `d963d66f` TODO echo
- Memory docs: `2c3965d3` tracked-vs-local

**Resulting `release.v1-5.no-vcs.md`:**

```markdown
# Release v1.5.0

- Removed model downloads, embeddings and MCP from QMD module.
- Agents instructions hardened
- Clarified the memory paths that are not tracked in VCS
```

Note how the four groups above became three bullets (the memory-docs change
folded in), no commit hash, prefix, or file path appears in the file, and every
line stays within 72 characters.

## Anti-patterns

- A commit-by-commit changelog (one bullet per commit).
- Commit hashes, `type(scope):` prefixes, or file paths in the release file.
- Bullet lines longer than 72 characters.
- Wrapping a bullet onto a second line when it fits on one.
- Listing every test/refactor/docs commit.
- Committing the `.no-vcs.md` file, or asking whether to.
