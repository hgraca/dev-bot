---
name: devbot:git-worktrees
description: "Use when you are about to make changes you will commit and are not already inside a linked git worktree — before editing, isolate the work in a worktree under <devbot_dir>/worktrees/, so the main checkout stays untouched."
---

# Git Worktrees

Every commit is made from a **linked worktree**, never from the main checkout. This keeps the
main checkout's checked-out branch untouched, and gives each task an isolated branch cut from the
**remote** default branch. This is the default; a project opts out with `"worktrees": false` (see
[Opting out](#opting-out)).

## Before editing (MUST)

First check whether worktrees are enabled for this project — exit `1` means the project opted out
(see [Opting out](#opting-out)), so work and commit in the main checkout as normal and this policy
does not apply:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" enabled
```

When they are enabled, detect where you are:

```bash
git rev-parse --git-dir --git-common-dir
```

- **Two different paths** — you are already in a linked worktree. Work and commit here; this
  policy is satisfied.
- **The same path** — you are in the main checkout. Create a worktree **before the first edit**:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create <branch>
```

`<branch>` is a descriptive name for the task — `feat/add-login`, `fix/null-token`. The tool:

- fetches `origin` and bases the new branch on `origin/<default>` — never on the main checkout's
  current branch, and never with an upstream (`--no-track`);
- puts the worktree at `<devbot_dir>/worktrees/<slug>` (default `.agents/worktrees/`), keeps that
  directory out of `git status`, and prints the absolute path;
- warns but proceeds if the main checkout is dirty.

The main checkout's branch is never switched. The tool fails if the branch or worktree path
already exists.

Before you start, confirm the main checkout is on the repository's default branch
(`git branch --show-current`). The finish merge lands there and never switches it, so starting
from another branch dead-ends the automated finish — if it is elsewhere, ask the human to switch
before you begin.

## Work in the worktree

The worktree is a separate checkout: **all edits use absolute paths under the printed worktree
path**, and **all git commands run with `-C <worktree>`**. It has no `.agents/` runtime farm —
skills, tools, and memory are served from the main checkout.

```bash
W="$(bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create feat/add-login)"
# edit "$W/src/..."
git -C "$W" add src/...
git -C "$W" commit -m "feat: add login"
```

Commit exactly as `devbot:git-commits` and `devbot:git-atomic-commits` describe — the commits just
land on the worktree branch.

## Finish

The primary agent's finish flow (`devbot:remember-session`) writes memories; commit them on the
**main checkout's local default branch** — that is where the finish flow runs, and committing
them there directly means only the work commits travel on the worktree branch.

Then **ask the user** whether to land the worktree branch and clean up. The main checkout must
already be on the default branch — the tool never switches it:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" merge <branch>   # plain merge into <default>
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" remove <branch>  # removes the dir; keeps the branch ref
```

`merge` fast-forwards the local default to `origin/<default>` first, then merges `--no-edit`;
on a conflict it aborts and leaves nothing merged. `remove` refuses a worktree with uncommitted
changes. Never push — the human decides.

## Opting out

Worktrees are the project default. A project (or the global config) turns the policy off with:

```jsonc
// .devbot.project.jsonc
{ "worktrees": false }
```

Agents then edit and commit in the main checkout as before, and `worktree.sh create` refuses with
a `FATAL:` — raw `git worktree` is still available to a human who wants one anyway.

## See also

- `devbot:git-commits` — message craft and the history-rewrite safety rule
- `devbot:git-atomic-commits` — grouping, ordering, and branch creation
