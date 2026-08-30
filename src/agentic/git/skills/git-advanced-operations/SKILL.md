---
name: devbot:git-advanced-operations
description: Advanced git history surgery — partial staging with git add -p, isolating unrelated work with stash pathspecs, splitting a commit that was already made, reordering or rewording a range of commits, verifying each commit builds independently, and recovering from a bad rebase or reset with reflog. Use when a single file contains several unrelated changes, when a commit needs breaking apart after the fact, when unrelated edits are in the way, when the user asks to reorder, reword, drop, or rewrite commits, or when a rebase or reset went wrong and work needs recovering. Also use for "how do I undo this", "I lost a commit", or "I committed too much at once".
---

# Advanced Git Operations

Techniques for cases where a plain `git add` + `git commit` isn't enough: changes tangled inside one file, commits that need breaking apart after the fact, and recovery when a rewrite goes wrong.

**Safety rule that governs everything below:** anything that rewrites history is safe on unpushed commits and dangerous on shared ones. Check before rewriting:

```bash
git branch -r --contains <sha>   # empty output means not pushed anywhere
git log --oneline @{upstream}..HEAD   # the range that is yours alone
```

If a commit is on a remote, rewriting forces every collaborator to reset. Get explicit approval, and on protected branches prefer a normal follow-up commit.

## Partial staging

When one file holds several unrelated changes:

```bash
git add -p path/to/file.ts
```

This walks the file hunk by hunk. The useful keys:

| Key | Action |
|---|---|
| `y` | stage this hunk |
| `n` | skip this hunk |
| `s` | split into smaller hunks |
| `e` | edit the hunk manually |
| `q` | quit staging |
| `?` | help |

`s` only splits where there's an unchanged line between changes. When two edits sit on adjacent lines, `e` is the way — it opens the patch so lines can be removed. In an edit buffer, delete `+` lines to leave them unstaged, and change `-` to a space to keep a line from being removed.

Always confirm the result:

```bash
git diff --cached      # what will be committed
git diff               # what's left behind
```

## Isolating unrelated work

Temporarily set aside changes that are in the way, using a pathspec so only the unrelated paths move:

```bash
git stash push -m "unrelated work" -- path/to/unrelated/
git add path/to/related/
git commit -m "feat: the focused change"
git stash pop
```

Verify with `git status` after popping. Inspect the stash before dropping anything:

```bash
git stash list
git stash show -p stash@{0}
```

`git stash push -- <path>` on a newly added file leaves it staged-but-stashed in a way that surprises people; check `git status` rather than assuming. For unrelated *untracked* files, add `-u`.

## Splitting a commit already made

For the most recent commit:

```bash
git reset HEAD~1               # undo the commit, keep the changes
git status                     # previously-new files now show as untracked
git add first/set
git commit -m "feat: first logical change"
git add second/set
git commit -m "feat: second logical change"
```

`git reset` defaults to `--mixed`: the commit disappears, changes stay in the working tree unstaged. Never use `--hard` here — it discards the changes being rescued.

For a commit further back, stop the rebase at that commit and split it in place:

```bash
git rebase -i <target-sha>^
# mark the target line: edit
git reset HEAD~1
git add first/set  && git commit -m "feat: first part"
git add second/set && git commit -m "feat: second part"
git rebase --continue
```

## Reordering, rewording, and dropping

```bash
git rebase -i <base>
```

In the todo list, reorder lines to reorder commits and change the leading verb:

| Verb | Effect |
|---|---|
| `pick` | keep as is |
| `reword` | keep the change, edit the message |
| `edit` | stop here to amend content |
| `squash` | merge into previous, combine messages |
| `fixup` | merge into previous, discard this message |
| `drop` | remove the commit |

Reordering commits that touch the same lines invites conflicts — expect to resolve them, and `git rebase --abort` if the result looks wrong. Add `--autostash` when uncommitted work needs to survive the rebase:

```bash
git rebase -i --autostash <base>
```

## Verifying commits are independently sound

An atomic commit should build on its own. Check a range mechanically rather than by eye:

```bash
git rebase --exec 'npm test' <base>        # run a command after each commit in range
```

That replays each commit and runs the command, stopping at the first failure. It rewrites the range, so the pushed-history rule applies. For a read-only check, walk the commits in a scratch worktree instead:

```bash
git worktree add /tmp/verify <sha>
cd /tmp/verify && npm ci && npm test
cd - && git worktree remove /tmp/verify
```

A worktree avoids disturbing the working copy, unlike checking out each commit in place.

## Recovery

Almost nothing is truly lost. Commits stay reachable via reflog for 90 days by default:

```bash
git reflog                     # every position HEAD has held
git reset --hard ORIG_HEAD     # undo the last rebase/merge/reset
git reset --hard HEAD@{5}      # go to a specific earlier position
```

`ORIG_HEAD` is set by rebase, merge, and reset — the fastest fix right after a bad one. For a commit orphaned by a rewrite, find it in the reflog and recover it without moving HEAD:

```bash
git cherry-pick <lost-sha>     # bring the change onto the current branch
git branch rescue <lost-sha>   # or park it on a branch to inspect first
```

If reflog doesn't show it, `git fsck --lost-found` lists dangling commits.

Mid-operation escape hatches:

```bash
git rebase --abort
git merge --abort
git cherry-pick --abort
```

The one genuinely destructive case is uncommitted changes lost to `git reset --hard` or `git checkout -- <file>`: those were never in the object database and cannot be recovered. Commit or stash before any risky operation.

## Related skills

- **atomic-commits** — grouping changes into logical commits in the first place
- **fixup-commits** — the `--fixup` and `--autosquash` workflow for correcting earlier commits
- **conventional-commits** — message format for the new messages these operations produce
