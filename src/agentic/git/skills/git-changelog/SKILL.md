---
name: devbot:git-changelog
description: "Use when a release or tag is being cut. Triggers on 'release notes', 'the changelog', 'sum up what changed'."
---

# Git Changelog (release file)

Produce a short, human-readable release file that summarises what changed in a
release. It is a changelog for a release/tag, **grouped by change** — not a
commit-by-commit log.

## Output contract

- **File name:** `release.v<VERSION>.no-vcs.md` at the repo root — the full
  release version with dots turned into dashes, e.g. release `v1.5.2` →
  `release.v1-5-2.no-vcs.md`, and the unstable four-part `v0.7.5.0` →
  `release.v0-7-5-0.no-vcs.md`.
- **Heading:** `# Release v<VERSION>` — the full version, e.g.
  `# Release v1.5.0`. A major of `0` marks a release as still unstable and
  carries four components, so the heading is `# Release v0.7.5.0` there and the
  file is `release.v0-7-5-0.no-vcs.md`.
- **The `.no-vcs.md` suffix is load-bearing:** it matches the `*no-vcs*`
  gitignore rule, so the file is **never committed**. Never `git add` it, and
  never ask where it goes — a release file is a local artifact. Writing or
  refreshing the file is the explicit direction `ignore.md` requires for a
  `no-vcs` path; do not stop to ask again.
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
  nothing a user or downstream module sees. Judge docs/infra by the reader: a
  docs change counts only when it changes what someone sees (the README, the
  docs front page, the licence); internal notes, generated tables and prose
  reflows do not.
- **State the change, never a placeholder.** "Agents instructions hardened"
  and "Clarified the memory paths" tell a reader nothing — replace each with
  what actually changed, or drop it.
- **Cap every bullet line at 72 characters** — the whole line including the
  `- ` marker. Keep a bullet to a single line; a second line is allowed only
  when a decision needs one sentence of rationale, and it is capped at 72 too.
- **When 72 characters force a trade-off, keep the outcome and drop the
  mechanism** — internal figures, full engine or flag lists, and how it works
  go first. The second line carries rationale, never extra facts.
- **Keep it tight:** one bullet per user-facing change — roughly 10–15 for a
  release of a few hundred commits, a handful for a small one. Merge changes
  only when they share a subsystem _and_ an outcome; never merge unrelated
  changes to hit a number, and never split one change across two bullets.

## Procedure

1. Determine the release range — **the entire range since the previous release
   tag**, `git log --oneline <last-tag>..HEAD`. Use the tag, not the default
   branch: `main` can lag the last tag. When refreshing an existing release
   file, re-audit that whole range — the file's age is not a boundary, and a
   change it omits may predate the file's last write.
2. Group the commits into logical changes.
3. Phrase each group as a product/decision statement.
4. Write or refresh `release.v<VERSION>.no-vcs.md`.
5. Do not commit it.
6. Verify the format before finishing — every line at most 72 characters.
   Nothing enforces this: the markdown formatter runs prettier with wrapping
   disabled, and no test parses release files.

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

**Resulting `release.v1-5-0.no-vcs.md`:**

```markdown
# Release v1.5.0

- Removed model downloads, embeddings and MCP from the QMD module.
- Agents instructions hardened: plan confirmation, no circumvention
- Memory notes split by tracking: work/ and thinking/ stay out of VCS
```

Note how the four groups above became three bullets (the memory-docs change
folded in), every bullet names a concrete change rather than a placeholder, no
commit hash, prefix, or file path appears, and every line stays within 72
characters.

## Anti-patterns

- A commit-by-commit changelog (one bullet per commit).
- Commit hashes, `type(scope):` prefixes, or file paths in the release file.
- Bullet lines longer than 72 characters.
- Wrapping a bullet onto a second line when it fits on one.
- A bullet that names no change — a placeholder the reader cannot act on.
- Listing every test/refactor/docs commit.
- Committing the `.no-vcs.md` file, or asking whether to.
