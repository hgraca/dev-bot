---
name: devbot:reconcile-work
description: "Use when wrapping up to reconcile the work folders and worktrees a session touched — the finish flow's third step, after devbot:grade-tools."
---

# Reconcile Work

Align the session's artifacts with reality at the end of a session. Every work item the session **started** ends up in `work/active/` (unfinished) or `work/archive/YYYY/MM/` (finished), so a skipped `make-plan` / `implement-story` move never leaves a started item stranded in `work/todo/`. And every **landed** worktree under `<devbot_dir>/worktrees/` is taken down with its local branch, so worktrees do not accumulate across sessions.

## When to Apply

- **Primary trigger**: the primary finish flow (see `devbot:agent-communication`), immediately after `devbot:remember-session` and `devbot:grade-tools`, before `[FINISHED]`.
- The user says "tidy the work folders", "reconcile the work items", "archive the finished work", or "clean up the worktrees".

## Scope

Reconcile only the work items **this session touched** — created via `devbot:make-plan`, promoted or edited via `devbot:implement-story`, or otherwise read or edited. Leave every untouched item in `work/todo/` and `work/active/` exactly where it is.

A **work-item root** is a top-level folder directly under `work/<state>/` (`YYYYMMDD-HHMMSS-NN-<slug>/`). An epic root carries its story sub-folders; moving the root moves them with it.

In a `supervisor: true` session, a work item lives in the vault of the project it concerns — reconcile each item in **its own** vault, and only coordination-level items in the supervisor's. A supervisor session may therefore touch several `work/` trees in one reconcile pass.

Worktrees follow the same rule but are found differently: each sits under its **owning project's** `<devbot_dir>/worktrees/`, and every subcommand takes `--project <owner>`. The flag is required in a `supervisor: true` session, whose root is a container repository with no worktrees of its own. Carry it in `project=(--project <owner>)`, set once per owning project, exactly as `devbot:git-worktrees` describes — empty in a normal project; `<root>` below is that project's main checkout.

## Procedure

1. **Remove the landed worktrees and their local branches.** Do this once per owning project the session touched — a `supervisor: true` session may have worked in several, and each keeps its worktrees under its own `<devbot_dir>/worktrees/`. For each project set `project=(--project <owner>)` exactly as `devbot:git-worktrees` describes (empty in a normal project), take `<root>` as that project's main checkout, and list what it holds:

   ```bash
   bash "${DEV_BOT_ROOT}/src/agentic/git/tools/worktree.sh" list "${project[@]}"
   ```

   It prints one `<path> <branch>` line per worktree. Decide from each worktree's **state**, never from who created it:

   | Worktree state                                       | Action                                  |
   | ---------------------------------------------------- | --------------------------------------- |
   | clean, everything pushed, work landed                | remove it, then delete its local branch |
   | clean, everything pushed, pull request still open    | keep — review feedback is fixed there   |
   | uncommitted changes, or commits not pushed to origin | keep — report it                        |
   | abandoned: no pull request, or one closed unmerged   | keep — ask the user                     |

   **Landed** means a pull request for `<branch>` into `<default>` was merged and none is still open. Run `gh` from `<root>` — in a `supervisor: true` session an unscoped query reads the container repository's pull requests, not the owner's:

   ```bash
   git -C <root> fetch --prune origin   # fresh refs; a branch deleted by a merge drops out here
   (cd <root> && gh pr list --head <branch> --base <default> --state all \
     --json number,state,headRefOid)
   ```

   A fetch that fails, or a `gh` call that errors, is **unknown** — not "no pull request": keep the worktree and report it, and reach the ancestry fallback only after a query that succeeded and returned nothing. Never swallow the error to manufacture an answer: `--prune` only drops a ref whose branch is really gone, because an unreachable remote fails the fetch outright. An `OPEN` pull request keeps the worktree. A `MERGED` one is the landed evidence **and** proof the branch was pushed — `origin/<branch>` is usually deleted on merge, so its absence must not block the cleanup; require instead that HEAD holds nothing past the merged head. With no pull request at all, fall back to ancestry against the refreshed `origin/<default>`:

   ```bash
   git -C <root> merge-base --is-ancestor <branch> origin/<default>
   ```

   Without `gh`, treat the worktree as not landed and keep it. **Check the state before calling the tool** — `remove` refuses a dirty worktree and exits:

   ```bash
   git -C <path> status --porcelain                     # empty = clean
   git -C <path> rev-list --count <headRefOid>..HEAD    # MERGED: 0 = nothing after it
   git -C <path> rev-list --count origin/<branch>..HEAD # no PR: 0 = nothing unpushed
   git -C <path> rev-list --count HEAD..origin/<branch> # no PR: 0 = nothing remote-only
   ```

   `origin/<branch>` that does not exist is not pushed, and a local branch behind its remote is not landed — the local ref can be an ancestor of `<default>` while the remote one is not — so both directions must count zero. Take it down one worktree at a time, so one failure is reported and the sweep continues with the next:

   ```bash
   if bash "${DEV_BOT_ROOT}/src/agentic/git/tools/worktree.sh" remove <branch> "${project[@]}"; then
     git -C <root> branch -D <branch>   # only once the worktree is gone
   else
     echo "WARN: kept <path> — branch left in place"
   fi
   ```

   `-D`, not `-d`: a squash-merged branch is not an ancestor of the default branch, so `-d` refuses. Local refs only.

2. **Reap the session's stale LSP servers.** opencode spawns one language server per directory it walks into and never tears a stale one down, so a long session accumulates idle `intelephense` / `*-language-server` processes that hold memory for the life of the process. Run:

   ```bash
   bash "${DEV_BOT_ROOT}/src/harnesses/opencode/lsp/reap.sh"
   ```

   It walks this session's opencode process, kills only servers that are provably not working — no CPU tick between two samples, or a working directory that no longer exists (a worktree step 1 just removed) — and logs its decisions to `.agents/logs/lsp-reap.log`. It is a silent no-op when there is nothing to reap, and a no-op outside opencode. Run it **unconditionally, without asking**: a reaped server respawns on demand the next time that directory is visited.

3. **List the touched work items.** From the session's own activity, collect the top-level `work/todo/` and `work/active/` folders this session created, started, or edited. If there are none, skip to the end — there is nothing left to reconcile.

4. **Classify each item** by its state this session:

   | Item state this session           | Action                                               |
   | --------------------------------- | ---------------------------------------------------- |
   | started, and now finished         | move to `work/archive/YYYY/MM/`                      |
   | started, still unfinished         | move to `work/active/` (from `todo/` if still there) |
   | created or planned, never started | leave in `work/todo/`                                |
   | already in `active/`, unfinished  | leave in `work/active/`                              |

5. **Decide "finished".** An item is finished when every acceptance criterion in its `backlog.md` is met and its work is committed and proven. When the state is genuinely ambiguous, ask the user which way it goes — do not guess.
6. **Move each item** with `mkdir -p <dest>` then `mv <src> <dest>`, preserving the folder name:
   - unfinished → `work/active/`
   - finished → `work/archive/YYYY/MM/`, using the **completion** year and month (`date +%Y/%m`).
7. **Stop** once every touched item sits in its correct state.

## MUST

- **Stay silent on the finish flow** — emit no narrative, exactly like `devbot:remember-session` and `devbot:grade-tools`; the only exceptions are a question when a state is genuinely ambiguous, and the report of a worktree kept back.
- **Reap LSP servers on every wrap-up, unattended** — step 2 runs whether or not the session touched a work item or a worktree, and is never put to the user for approval; its only trace is `.agents/logs/lsp-reap.log`.
- **Remove a worktree only when it is clean, fully pushed, and landed** — then delete its local branch, and only then.
- **Run the sweep once per owning project**, and let one unremovable worktree continue to the next.
- **Keep every worktree the gate does not clear**, and name it in the wrap-up report so the user knows it is still there and why.
- Reconcile only work **items** this session touched; leave all others alone — a worktree is gated by its state, not by who created it.
- Move the work-item **root**; never split a folder's files across states.
- Use plain `mkdir -p` + `mv` — `work/` is gitignored local scratch, never `git add` or commit it.
- Place new archives at `work/archive/YYYY/MM/`; never restructure existing archive layouts.
- Ask the user only when an item's finished / unfinished state, or a worktree's abandoned work, is genuinely ambiguous.

## MUST NOT

- Do not reconcile or audit `work/` items the session never touched.
- Do not commit, stage, or push anything under `work/` (gitignored local scratch).
- Do not re-home existing `archive/` folders to the `YYYY/MM` shape.
- Do not delete a branch that has an open pull request, commits not on `origin`, or a worktree still standing.
- Do not delete a remote branch, and do not force `git worktree remove` or discard changes to make one removable.
- Do not remove a worktree outside `<devbot_dir>/worktrees/` — the main checkout is not one to clean up.
