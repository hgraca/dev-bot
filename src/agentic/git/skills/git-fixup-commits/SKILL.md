---
name: devbot:git-fixup-commits
description: Record a correction against the earlier commit it belongs to using git commit --fixup, then optionally fold it in with an approved autosquash rebase. Use whenever a change fixes something introduced by a commit that is unique to the current branch rather than being new work — including requests like "fixup", "squash this into", "amend an earlier commit", "fold this in", "autosquash", "fix that typo from three commits ago", or "tidy my branch before review". Also use when the user is about to add a "fix typo" or "address review comment" commit that really belongs inside an earlier one.
---

# Fixup Commits

When a change corrects a commit that is unique to the current branch, record it as a fixup against that commit instead of adding a loose "fix typo" commit. The eventual history stays atomic, and the rewrite stays a separate, explicitly approved step.

The core distinction: **creating a fixup commit is always safe** — it only adds a commit. **Squashing it rewrites history** — it does not.

## Workflow

### 1. Identify the target commit

```bash
git log --oneline main..HEAD                 # list of commits unique to the current branch — the safe candidates
git log --oneline -10
git blame -L <start>,<end> -- path/to/file   # which commit introduced these lines
git log -S '<changed string>' --oneline      # commits that added/removed a string
git log --oneline -G '<regex>'               # commits whose diff matches a pattern
```

Target the commit that _introduced_ the thing being corrected, not merely a later commit that touched the same file. `git blame` on the pre-correction version of the line is the most reliable signal. Confirm with `git show --stat <target-sha>`.

If the correction spans lines from two different commits, split it and fix up each part separately. A fixup belonging to two commits belongs to neither.

### 2. Stage only the corrective changes

```bash
git add -p path/to/file      # or: git add <specific paths>
git diff --cached            # verify the staged diff is ONLY the correction
```

Nothing else may ride along. Anything extra gets silently rewritten into an old commit, which is much harder to notice later than a bad standalone commit.

### 3. Create the fixup commit

```bash
git commit --fixup=<target-sha>
```

This writes a commit titled `fixup! <target subject>` — the marker `--autosquash` looks for later.

### 4. Do not autosquash automatically

Stop here unless the user asked for history cleanup. The fixup commit is a valid, informative state: it records "this belongs to that commit" without destroying anything. Report what was created and leave the squash decision to the user.

### 5. Before rewriting, show the plan and ask for approval

```bash
git log --oneline <base>..HEAD    # the commits to be rewritten

# Print the exact autosquash plan without executing it.
# The editor prints the todo list then fails, so the rebase aborts untouched.
GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' \
  git rebase -i --autosquash <base>
```

That prints the `pick`/`fixup` lines showing precisely which commit folds into which, exits non-zero, and leaves history unchanged. There is no `git rebase --dry-run`; this is the substitute. (Using bare `cat` here hangs — it reads stdin — so keep the `"$1"`.)

State the base, how many commits are affected, which fixups fold into which targets, and whether any of them have been pushed. Then wait for a yes.

### 6. Apply the squash

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>
```

`GIT_SEQUENCE_EDITOR=:` replaces the todo-list editor with a no-op (`:` is a shell builtin that succeeds silently), accepting the pre-arranged list without opening an editor. This is safe _only because_ the plan was reviewed in step 5 — never combine it with an unreviewed rebase.

### 7. Never rewrite shared or already-pushed history without explicit approval

Check before proposing anything in step 5:

```bash
git branch -r --contains <target-sha>   # empty output means not pushed anywhere
git log --oneline main..HEAD            # the list of commits unique to the current branch
git status -sb                          # ahead/behind counts
```

If the target commit exists on a remote, say so plainly and explain the consequence: everyone tracking the branch will need to reset or force-pull. A force push needs the user's explicit go-ahead, and on a protected or shared branch the right answer is usually a normal follow-up commit instead.

## Verify the result

```bash
git log --oneline <base>..HEAD    # no fixup! subjects should remain
git diff <base>..HEAD | git hash-object --stdin   # run before and after; hashes must match
```

The second check is the real test: squashing fixups reorganizes history without altering the final tree, so the cumulative diff must be identical before and after. This only holds when `<base>` is an ancestor the rebase does _not_ rewrite — with `--root` the base commit is itself rewritten, so compare `git rev-parse HEAD^{tree}` instead.

## Choosing the marker

| Command                           | Resulting commit               | On autosquash                                 |
| --------------------------------- | ------------------------------ | --------------------------------------------- |
| `git commit --fixup=<sha>`        | `fixup! <subject>`             | Folds in, target's message kept               |
| `git commit --squash=<sha>`       | `squash! <subject>`            | Folds in, both messages offered for editing   |
| `git commit --fixup=amend:<sha>`  | `amend! <subject>`             | Folds in content **and** replaces the message |
| `git commit --fixup=reword:<sha>` | `amend! <subject>`, empty tree | Replaces the message only, no content change  |

Default to `--fixup`. Reach for `amend:` or `reword:` when the original message was wrong or the change makes it inaccurate. `reword:` needs a clean index since it carries no content.

**Important for `amend:` and `reword:`** — git opens an editor prefilled with two lines:

```
amend! feat: add thing        <- the marker; leave this line alone
feat: add thing               <- the replacement message; edit this
```

Edit the second line and below. Deleting or altering the first line destroys the marker, and autosquash will silently leave the commit standing as an ordinary commit instead of folding it in.

Multiple fixups may target the same commit; autosquash applies them in commit order.

## Choosing the rebase base

The base must be an ancestor of the oldest commit being modified, and as recent as possible to limit the blast radius:

```bash
git rebase -i --autosquash main             # everything unique to the current branch — usually right
git rebase -i --autosquash <target-sha>^   # tightest base when fixing one commit
git rebase -i --autosquash --root          # entire history — rarely wanted
```

`<target-sha>^` fails on a root commit, where `--root` is needed. Add `--autostash` if the user has uncommitted work to preserve across the rebase.

## Autosquash matching

`--autosquash` reorders the todo list so each `fixup!`/`squash!`/`amend!` commit sits directly after its target, marked to fold in. It matches on the commit _subject line_, or on the sha recorded when `--fixup=<sha>` was used. Two consequences:

- If a target's subject is later reworded, subject-based matching breaks and the fixup stays a standalone commit. Always check `git log --oneline` after a rebase.
- `rebase.autosquash=true` in the user's config makes this the default for every interactive rebase. Check with `git config --get rebase.autosquash` — if set, a plain `git rebase -i` also folds fixups, which may surprise the user.

## When the rebase goes wrong

```bash
git rebase --abort        # bail out, return to pre-rebase state
git rebase --continue     # after resolving conflicts
```

If a rebase completed and the result is wrong, the old history is still reachable:

```bash
git reset --hard ORIG_HEAD    # quickest recovery right after a bad rebase
git reflog                    # find the pre-rebase HEAD, e.g. HEAD@{5}
git reset --hard HEAD@{5}
```

Conflicts during an autosquash rebase usually mean the fixup was aimed at the wrong target, or a later commit already touched those lines. Abort, re-check with `git blame`, and retarget rather than resolving through it.

## When not to use fixup

- **The commit is on a shared or protected branch** → normal follow-up commit
- **The correction is a real behavioural change worth its own history entry** → new atomic commit
- **The target is the most recent commit with nothing stacked on it** → `git commit --amend` is simpler
- **The branch is under review with per-commit comments** → rewriting detaches them; ask first
- **The project squash-merges every PR** → final history has one commit anyway, though fixups still help reviewers follow an in-progress branch

## Related skills

- **atomic-commits** — splitting new work into logical commits
- **advanced-operations** — partial staging, splitting an existing commit, reflog recovery in depth
- **conventional-commits** — message format for the replacement messages used by `amend:` and `reword:`
