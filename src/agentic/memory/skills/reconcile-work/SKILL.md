---
name: devbot:reconcile-work
description: "Use when wrapping up to reconcile the artifacts a session touched — work folders, worktrees and thinking files — the finish flow's housekeeping step, after devbot:remember-session and devbot:grade-tools, ahead of devbot:improve-reviewing when the session ran a code review loop. Triggers on 'wrap up', 'wrapping up', 'let's wrap', 'tidy the work folders', 'clean up my scratch notes'."
---

# Reconcile Work

Align the session's artifacts with reality at the end of a session. Every work item the session **started** ends up in `work/active/` (unfinished) or `work/archive/YYYY/MM/` (finished), so a skipped `make-plan` / `implement-story` move never leaves a started item stranded in `work/todo/`. And every **landed** worktree under `<devbot_dir>/worktrees/` is taken down with its local branch and the containers booted for it, so worktrees and containers do not accumulate across sessions — while the volumes it leaves behind are named for the user to judge, never deleted on a project label alone. And every `thinking/` file the session wrote is deleted, so scratch notes do not accumulate either.

## When to Apply

- **Primary trigger**: the primary finish flow (see `devbot:agent-communication`), immediately after `devbot:remember-session` and `devbot:grade-tools`, and followed by `devbot:improve-reviewing` when the session ran a code review loop; before `[FINISHED]`.
- The user says "wrap up", "wrapping up", "let's wrap", "tidy the work folders", "reconcile the work items", "archive the finished work", "clean up the worktrees", or "clean up my scratch notes". Only the session-ending phrasings ("wrap up", "wrapping up", "let's wrap") trigger step 3's removal of this session's `thinking/` files; the others run mid-session and skip it.

## Scope

Reconcile only the work items **this session touched** — created via `devbot:make-plan`, promoted or edited via `devbot:implement-story`, or otherwise read or edited. Leave every untouched item in `work/todo/` and `work/active/` exactly where it is.

A **work-item root** is a top-level folder directly under `work/<state>/` (`YYYYMMDD-HHMMSS-NN-<slug>/`). An epic root carries its story sub-folders; moving the root moves them with it.

In a polyrepo session, a work item lives in the vault of the project it concerns — reconcile each item in **its own** vault, and only coordination-level items in the polyrepo's. A polyrepo session may therefore touch several `work/` trees in one reconcile pass.

Worktrees follow the same rule but are found differently: each sits under its **owning project's** `<devbot_dir>/worktrees/`, and every subcommand takes `--project <owner>`. The flag is required in a `workspace.type: "polyrepo"` session, whose root is a container repository with no worktrees of its own. Carry it in `project=(--project <owner>)`, set once per owning project, exactly as `devbot:git-worktrees` describes — empty in a normal project; `<root>` below is that project's main checkout.

## Procedure

1. **Remove the landed worktrees with their local branches and dev environments.** Do this once per owning project the session touched — a `workspace.type: "polyrepo"` session may have worked in several, and each keeps its worktrees under its own `<devbot_dir>/worktrees/`. For each project set `project=(--project <owner>)` exactly as `devbot:git-worktrees` describes (empty in a normal project), take `<root>` as that project's main checkout, and list what it holds:

   ```bash
   bash "${DEV_BOT_ROOT}/src/agentic/git/tools/worktree.sh" list "${project[@]}"
   ```

   It prints one `<path> <branch>` line per worktree. Decide from each worktree's **state**, never from who created it:

   | Worktree state                                       | Action                                  |
   | ---------------------------------------------------- | --------------------------------------- |
   | clean, everything pushed, work landed                | remove it, then delete its local branch |
   | clean, everything pushed, pull request still open    | keep — review feedback is fixed there   |
   | uncommitted changes, or commits not pushed to origin | keep — report it                        |
   | abandoned: no pull request, or one closed unmerged   | keep — report it                        |

   **Landed** means a pull request for `<branch>` into `<default>` was merged and none is still open. Run `gh` from `<root>` — in a `workspace.type: "polyrepo"` session an unscoped query reads the container repository's pull requests, not the owner's:

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

   `origin/<branch>` that does not exist is not pushed, and a local branch behind its remote is not landed — the local ref can be an ancestor of `<default>` while the remote one is not — so both directions must count zero. Take it down one worktree at a time — **environment first, then the directory, then the branch** — so one failure is reported and the sweep continues with the next:

   ```bash
   # Stop the containers this worktree owns — matched on both of their labels, so a project name
   # shared with another checkout cannot reach them. Volumes and networks carry only the project
   # label, which cannot prove ownership: they are left for the report instead.
   drop_env() {
     local ids
     ids=$(docker ps -aq --filter "label=com.docker.compose.project=$1" \
                         --filter "label=com.docker.compose.project.working_dir=$2")
     [ -z "$ids" ] && return 0
     docker rm -f $ids
   }

   # 1. the dev environment booted for this worktree, found from the compose labels.
   # A discovery that fails is not an empty result: it is reported and nothing is assumed.
   dirs=$(set -o pipefail; docker ps -a --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' \
   | sort -u) || { echo "WARN: docker is not answering — no environment torn down" >&2; dirs=""; }
   printf '%s\n' "$dirs" | while IFS=$'\t' read -r env dir; do
     case "$dir" in
       <path>|<path>/*) drop_env "$env" "$dir" && echo "torn down $env" \
                         || echo "WARN: $env left running — teardown failed" >&2 ;;
     esac
   done

   # 2. the directory, then its local branch
   if bash "${DEV_BOT_ROOT}/src/agentic/git/tools/worktree.sh" remove <branch> "${project[@]}"; then
     git -C <root> branch -D <branch>   # only once the worktree is gone
   else
     echo "WARN: kept <path> — branch left in place"
   fi
   ```

   `-D`, not `-d`: a squash-merged branch is not an ancestor of the default branch, so `-d` refuses. Local refs only.

   **The environment is part of the worktree, not of the checkout.** A worktree booted with its own compose project (`make up-worktree`) runs containers named for that worktree, and `remove` deletes the directory only: the containers outlive it, pointing at bind mounts that no longer exist, and no session owns them any more. `compose` stamps every container with its project and the directory it ran from, so that pair finds them — and the labels keep the path after the directory is gone. Stop them by those labels, not with `docker compose down`: `-p` names the project but never loads _its_ configuration, so a `down` run from a checkout that has a compose file of its own resolves the wrong stack, and once the directory is gone there is no file left to load. **Containers only, and matched on both labels.** A project name is not proof of ownership — it is built from the worktree's directory name, so two checkouts of the same repository can share one — while a volume or a network carries that name and nothing else, so a sibling checkout's data cannot be told apart from this one's, even after its containers are stopped. Volumes are therefore left alone and named in the wrap-up report for the user to judge, and a project's network is left too, recreated by its next `up`. When the project ships its own teardown target (`make down-worktree`, which also drops the worktree's hosts entry), run that while the directory still exists; the container sweep covers a project without one, and every worktree whose directory is already gone. A teardown that fails is reported and the removal proceeds: the orphan sweep below finds that environment again.

   **Kept worktrees keep their environment** — every row of the table that says _keep_ leaves the containers running, because the session that resumes there boots into them and a pull request still open is fixed there. Bring down only the environments of worktrees this step removes.

   **Then sweep the orphans.** A worktree removed without its environment — by an earlier session, or by a teardown that failed above — leaves containers started from a directory under `<devbot_dir>/worktrees/` that is now gone. Nothing owns them, and no worktree will ever stop them, so scan for those once per owning project, stop them with the same `drop_env`, and name them in the wrap-up report:

   ```bash
   dirs=$(set -o pipefail; docker ps -a --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' \
   | sort -u) || { echo "WARN: docker is not answering — no sweep run" >&2; dirs=""; }
   printf '%s\n' "$dirs" | while IFS=$'\t' read -r env dir; do
     case "$dir" in
       <devbot_dir>/worktrees/*) ;;
       *) continue ;;
     esac
     rel="${dir#"<devbot_dir>/worktrees/"}"
     [ -d "<devbot_dir>/worktrees/${rel%%/*}" ] && continue
     drop_env "$env" "$dir" && echo "reaped $env" \
       || echo "WARN: $env left running — teardown failed" >&2
   done
   ```

   Volumes cannot be swept the same way: they carry the project name but never the directory that made them, and a project whose containers are already stopped does not appear in `docker ps` at all. Print the ones whose project has nothing running:

   ```bash
   docker volume ls --filter label=com.docker.compose.project \
     --format '{{.Label "com.docker.compose.project"}}\t{{.Name}}' \
   | while IFS=$'\t' read -r env vol; do
     [ -n "$env" ] && [ -n "$vol" ] || continue
     [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=$env")" ] || continue
     printf 'project %s: docker volume rm %s\n' "$env" "$vol"
   done
   ```

   Name them in the wrap-up report with the command that removes each, and let the user judge which of those projects were worktrees before running it — this step never runs it. Networks are left too, without a report: compose recreates each project's network on its next `up`, so a dangling one costs a name and holds no data.

2. **Reap the session's stale LSP servers.** opencode spawns one language server per directory it walks into and never tears a stale one down, so a long session accumulates idle `intelephense` / `*-language-server` processes that hold memory for the life of the process. Run:

   ```bash
   bash "${DEV_BOT_ROOT}/src/harnesses/opencode/lsp/reap.sh"
   ```

   It walks this session's opencode process, kills only servers that are provably not working — no CPU tick between two samples, or a working directory that no longer exists (a worktree step 1 just removed) — and logs its decisions to `.agents/logs/lsp-reap.log`. It is a silent no-op when there is nothing to reap, and a no-op outside opencode. Run it **unconditionally, without asking**: a reaped server respawns on demand the next time that directory is visited.

3. **Remove the thinking files this session wrote.** Run this step **only on the session-ending trigger** — the finish flow, or a "wrap up". A mid-session "tidy the work folders" skips it, because the session's drafts and WIP notes are still live.

   `thinking/` is scratch space, not a second memory vault, and it is shared: a polyrepo session dispatches several scouts that each write their report into it, and other sessions may be working in the same workspace. Delete exactly the files **this session wrote** — the drafts, checkpoints and subagent reports produced during this session, which you know from the work you did. Never pick files by pattern, age, or a guess from the filename: a file you did not write belongs to someone else, and another session may still be writing it. If you can no longer attribute a file — the session was compacted or resumed — leave it and name it in the wrap-up report rather than guess.

   **Promotion is not yours** — `devbot:remember-session` has already promoted the lasting value and is the only writer of memory notes, so this step only deletes. **Leave tool-managed state alone**: the dot-prefixed `thinking/.auto-recover-*` files are runtime locks and attempt counters written by the harness, not scratch — never delete them. `thinking/` is otherwise gitignored local scratch: never stage or commit anything from it.

4. **List the touched work items.** From the session's own activity, collect the top-level `work/todo/` and `work/active/` folders this session created, started, or edited. If there are none, skip to the end — there is nothing else to reconcile.

5. **Update each touched item's delivery record before moving it.** A work item is the vault's answer to "what happened to this?", and the folder it sits in only says where it is. Rewrite the item's own `backlog.md` so it matches what this session actually did:

   - **Write one `**Delivery**` line beside `**Status**`** — never repurpose `**Status**`, which is the planning contract's (`DRAFT` | `IN REVIEW` | `FINAL`, owned by `devbot:make-plan`; a plan-only item keeps `DRAFT`). The line says what shipped and in which form, because the workflow in use decides that: `merged` with the pull request (`[GET-E/dev-bot#151](…)`) under the worktrees workflow, `landed` with the commit on the default branch under the trunk workflow. Add `— partial:` naming what remains when only part shipped, `— stopped by decision (date)` when work ended without meeting the criteria, and `— none: started, nothing landed yet` when the session began the item and delivered nothing at all. **Exactly one such line exists**: when it is already there, rewrite it in place — never append a second, or the item accumulates conflicting histories.
   - **What changed underneath it** — when a session only delivered part of an item, say which findings/acceptance criteria are now met and which remain, rather than leaving the original brief to imply nothing happened.
   - **The ticket, when the item has one** — a Jira ticket gets the same treatment through `devbot:jira-workflow`: move it when its status changed, and append what landed. A ticket is not closed by a landed pull request alone; close it when the work is finished.

   This is a record update, not an audit: one delivery line and the facts that moved it. It is the only part of this skill that writes to a work item, and it happens **before** the classification below, because the correct folder follows from the recorded state.

6. **Classify each item** by its state this session:

   | Item state this session           | Action                                               |
   | --------------------------------- | ---------------------------------------------------- |
   | started, and now finished         | move to `work/archive/YYYY/MM/`                      |
   | started, still unfinished         | move to `work/active/` (from `todo/` if still there) |
   | created or planned, never started | leave in `work/todo/`                                |
   | already in `active/`, unfinished  | leave in `work/active/`                              |

7. **Decide "finished".** An item is finished when every acceptance criterion in its `backlog.md` is met and its work is committed and proven. When the state is genuinely ambiguous, leave the item where it is and name it in the wrap-up report — the finish flow never waits for an answer.
8. **Move each item** with `mkdir -p <dest>` then `mv <src> <dest>`, preserving the folder name:
   - unfinished → `work/active/`
   - finished → `work/archive/YYYY/MM/`, using the **completion** year and month (`date +%Y/%m`).
9. **Stop** once every touched item sits in its correct state and its record says why.

## MUST

- **Stay silent on the finish flow** — emit no narrative, exactly like `devbot:remember-session` and `devbot:grade-tools`; the only exception is the report of what was kept back — a worktree, or a `thinking/` file this session cannot attribute to itself.
- **Reap LSP servers on every wrap-up, unattended** — step 2 runs whether or not the session touched a work item or a worktree, and is never put to the user for approval; its only trace is `.agents/logs/lsp-reap.log`.
- **Remove every `thinking/` file this session wrote**, on the session-ending trigger only — and delete-only: never write `latent/` or any memory note from this step. A file this session did not write is reported, never deleted.
- **Remove a worktree only when it is clean, fully pushed, and landed** — then delete its local branch, and only then.
- **Take a removed worktree's dev environment down with it** — the containers carrying both its project and its working directory, matched on both labels, before the directory goes; volumes carry only the project name and are left for the report, networks are left for compose to recreate, and a worktree left standing keeps its environment.
- **Sweep the orphaned environments once per owning project** — a compose project under `<devbot_dir>/worktrees/` whose directory is gone has its containers stopped and is named in the report, while its volumes are reported, never deleted.
- **Run the sweep once per owning project**, and let one unremovable worktree continue to the next.
- **Keep every worktree the gate does not clear**, and name it in the wrap-up report so the user knows it is still there and why.
- Reconcile only work **items** this session touched; leave all others alone — a worktree is gated by its state, not by who created it.
- **Update every touched item's delivery record, then move it** — a `DRAFT` left beside a merged pull request makes the next session re-derive what happened, and the folder alone never says why an item is unfinished. Write the `**Delivery**` line; never repurpose the planning `**Status**`.
- Move the work-item **root**; never split a folder's files across states.
- Use plain `mkdir -p` + `mv` — `work/` is gitignored local scratch, never `git add` or commit it.
- Place new archives at `work/archive/YYYY/MM/`; never restructure existing archive layouts.
- When an item's finished / unfinished state, or a worktree's abandoned work, is genuinely ambiguous, keep it and report it — never ask during the finish flow.

## MUST NOT

- Do not reconcile or audit `work/` items the session never touched.
- Do not commit, stage, or push anything under `work/` (gitignored local scratch).
- Do not re-home existing `archive/` folders to the `YYYY/MM` shape.
- Do not delete a branch that has an open pull request, commits not on `origin`, or a worktree still standing.
- Do not delete a remote branch, and do not force `git worktree remove` or discard changes to make one removable.
- Do not remove a worktree outside `<devbot_dir>/worktrees/` — the main checkout is not one to clean up.
- Do not bring down the environment of a worktree that is still standing, or of anything outside `<devbot_dir>/worktrees/` — the main checkout's stack and the shared services are other sessions' to keep.
- Do not remove a compose volume or network by its project label — two checkouts can share the name, and a stopped sibling leaves nothing to tell its data from this worktree's. A volume is reported for the user to judge; a network is recreated by the next `up`.
- Do not leave one of this session's `thinking/` files behind — and do not delete one this session did not write, or `thinking/.auto-recover-*`, which is runtime state.
