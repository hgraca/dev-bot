---
name: devbot:git-atomic-commits
description: Split accumulated git changes into clean, atomic commits where each one is a single logical change that builds and reviews on its own. Use whenever a working tree has piled up unrelated edits, when many files are staged together, or when the user asks to "commit my changes", "split this up", "organize my changes", "make atomic commits", "clean up before the PR", or wants help deciding what belongs in which commit. Also use when the user is about to make one large catch-all commit, even if they did not ask for help splitting it.
---

# Atomic Commits

Turn a pile of unrelated changes into a sequence of commits where each one is a single logical change. The test of an atomic commit: it can be reviewed on its own, it leaves the codebase working, and it can be reverted without dragging unrelated work with it.

Always assume there are other agents working in files in the same branch, so make sure at all times to commit only your changes.

The opposite is a "checkpoint commit" — committing linearly as you go, like a save point in a video game. Avoid it: new changes that belong to an existing commit should be folded into that commit, not made into a new one; changes serving different purposes never share a commit.

Two hygiene rules follow:

- Use `git mv` for renames, not a manual delete + add, so git tracks the move and preserves file history.
- Never commit paths ignored by git — a gitignored file or folder must not be committed unless a human explicitly asks for it.

## Workflow

### 1. Survey what's actually changed

```bash
git status
git diff --stat          # scale of the change
git diff                 # unstaged detail
git diff --cached        # already-staged detail
```

Read the diff before grouping. Grouping by directory or filename is a guess; grouping by what the change _does_ is the goal.

### 2. Group changes by intent

Sort the changes into logical units, one commit per unit:

- **feat** — new capability
- **fix** — corrected behaviour
- **refactor** — restructuring with no behaviour change
- **docs** — documentation
- **test** — tests
- **chore** — maintenance, deps, config

One file often contains two intents (a bug fix plus an unrelated rename). That's a signal to stage in pieces rather than to give up and combine — see the advanced-operations skill for `git add -p` and stash isolation.

### 3. Commit each group

Stage only the files for the current logical change, verify, then commit:

```bash
git add path/to/related/files
git diff --cached              # confirm nothing extra rode along
git commit -m "feat: add user authentication"

git add path/to/other/files
git diff --cached
git commit -m "fix: correct null check in validator"
```

The `git diff --cached` step is what keeps commits atomic. Skipping it is how unrelated changes leak in.

### 4. Verify and push

```bash
git log --oneline -10
git push origin <branch>
```

## Commit order

Order commits so the history is bisectable and each step stands on its own:

1. **Documentation** — lowest risk, no behaviour change
2. **Tests** — verification scaffolding
3. **Bug fixes** — independent corrections
4. **Features** — the main change
5. **Refactoring** — cleanup on top of working code

When changes genuinely depend on each other, dependency order overrides this list: shared or base code first, then the code that consumes it, then the tests covering both. A commit that references code introduced by a later commit is not atomic — it doesn't build.

## Example

Changes to a login page, an avatar fix, a README update, and new tests:

```bash
git add README.md
git commit -m "docs: update README with login instructions"

git add tests/login.test.ts
git commit -m "test: add login component tests"

git add src/components/Avatar.tsx
git commit -m "fix: correct avatar display on retina screens"

git add src/pages/Login.tsx src/components/LoginForm.tsx
git commit -m "feat: add login page with validation"

git push origin feature/login
```

Four independent commits: the avatar fix can be cherry-picked to a release branch, and the README change can be reverted, without touching the login feature.

## Deciding how finely to split

More commits is usually the better error. Two rules of thumb:

- If the commit message needs the word "and", it's probably two commits.
- If a reviewer would want to approve half of it and question the other half, split it.

The limit is the working-state rule: don't split so finely that intermediate commits fail to build. A commit adding a function call plus the commit adding the function belong together if neither compiles alone.

## Migrations (MUST — no DB BC breaks)

A database migration is a special atomic-commit case with a hard rule: it never rides in the same commit as the code that depends on it, and it never introduces a backward-incompatible schema break. A task with a migration splits into 2–3 commits:

1. **Expand** — additive migration (new nullable column/table) so old and new code both work.
2. **Migrate** — the new code against the migrated schema.
3. **Contract** — a follow-up migration removing now-unused columns/tables once the old code is retired.

Never drop/rename in place, and never bundle a destructive migration with an additive one. See `deprecation-and-migration` for the schema mechanics.

## Related skills

- **conventional-commits** — the `<type>(<scope>): <description>` message format, type reference, and breaking-change notation
- **advanced-operations** — partial staging with `git add -p`, stash isolation, splitting a commit that was already made, verifying each commit builds
- **fixup-commits** — when the change corrects a commit that already exists on this branch, rather than being new work
