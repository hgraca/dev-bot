---
name: devbot:commit-memories
description: "Use at wrap-up to publish the session's captured memories and global lessons. Triggers on 'commit the memories', 'publish the session memories'."
---

# Commit Memories and Lessons Learned

The finish flow's memory capture writes notes into one or more projects' vaults. This skill turns those
writes into reviewable commits: a branch and a pull request in the repository that owns each note, so a
memory is never stranded on a local default branch and a cross-project lesson is never left untracked in
the toolkit.

Three rules make it safe rather than noisy:

- **The project the note belongs to owns the pull request.** A project-vault note goes to that
  project's repository under the vault title; a global lesson goes to the dev-bot repository under the
  global-memories title, where the shared store lives. One standing pull request per stream and
  repository.
- **Unattended.** The finish flow asks nothing: commit, push and open or update the standing pull
  request directly. The pull request's review is where a note is accepted, edited or dropped.
- **One standing pull request per stream.** Every capture's vault notes go to the same vault pull
  request, and its global lessons to the same global-memories pull request; a second one splits the
  review and the history of what the agents learned.

## When to Apply

- `devbot:remember-session` step 4, after the capture has written its notes.
- The user asks to commit or publish the session's memories.

## Preconditions

- `gh` is installed and authenticated (`gh auth status`). If it is not, stop and report it — never guess at credentials.
- The repository's `origin` is reachable and pushable. A repository that fails either test is skipped and reported, not forced.

## Procedure

### 1. Collect the capture's files and group them by repository and stream

Take the files the capture created or modified — never the whole vault. Resolve each to the repository
that owns it and the stream it belongs to:

| File written under                                           | Stream | Owning repository         | Standing title                                                       |
| ------------------------------------------------------------ | ------ | ------------------------- | -------------------------------------------------------------------- |
| `<project>/<devbot_dir>/memory/...`                          | vault  | that project's repository | `chore(agents): commit memories and lessons learned`                 |
| `latent/global/<tech>/...` (a symlink into the global store) | global | the dev-bot repository    | `chore(global-memories): commit global memories and lessons learned` |
| `$DEV_BOT_ROOT/storage/global-memories/<tech>/...`           | global | the dev-bot repository    | `chore(global-memories): commit global memories and lessons learned` |

Group by **repository and stream**: one repository can carry both a vault pull request and a
global-memories pull request — never mix the two in one branch or pull request.

A global note may be named by its project-vault path —
`.agents/memory/latent/global/<tech>/note.md` — which is a symlink. Resolve it physically
(`cd "$(dirname <path>)" && pwd -P`) and use its dev-bot-relative target
(`storage/global-memories/<tech>/note.md`) for every later check, copy and stage; never use the
symlink path.

Resolve the repository root with `git -C <dir> rev-parse --show-toplevel`. A global note resolving
into the dev-bot checkout is expected, not an error; an answer that matches neither the note's owning
project's checkout nor the dev-bot checkout means the note is somewhere else — report it, do not
commit through a symlink. In a polyrepo session, resolve each project-vault note with
`devbot tool project-for-path <file>` and use the owner's own `devbot_dir` and repository; never the
polyrepo root.

A directory that is not a git repository is skipped with a **notice** line in the owning project's
`.agents/logs/memory-index.log` — no warning, no failure.

### 2. Apply the tracking gate

- **Project-vault notes** are published only when the owning project's effective `commit_memory` is
  `true` (`devbot tool project-for-path <file> --key commit_memory` — project-first, global-fallback;
  absent everywhere means `false`) **and** `git -C <root> check-ignore <path>` reports the file is not
  ignored. That probe exits 0 when the path **is** ignored (skip it), 1 when it is not (publish it),
  and 128 on error — a 128 is a stop-and-report, never a publish. A blanket `.gitignore` can shadow
  the surgical excludes even with `commit_memory: true`; check the file itself. A skipped file stays
  local: there is nothing to fix and nothing to ask.
- **Global-store notes** are always published: the dev-bot repository tracks
  `storage/global-memories/` by design, whatever a project's `commit_memory` says.
- Drop any group left with no file to publish.

### 3. Find the standing pull request for each group

Run `gh` from that repository's root (or pass `--repo <owner/name>`), with the default branch read from
`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. Fetch the base explicitly — an
installed toolkit is a shallow, tag-only clone, where the configured refspec never creates
`refs/remotes/origin/<default>`:

```bash
git -C "$root" fetch origin "+refs/heads/$default:refs/remotes/origin/$default"
# a shallow clone fetches the same ref at depth 1, so it stays small:
git -C "$root" fetch --depth 1 origin "+refs/heads/$default:refs/remotes/origin/$default"
```

Use the `--depth 1` form only when `git -C "$root" rev-parse --is-shallow-repository` prints `true`.
A plain `git fetch origin` is not enough. When the fetch fails or the ref still does not resolve,
report the repository and skip it — never fall back to the local default.

```bash
# vault group
gh pr list --state open --limit 200 --json number,url,headRefName,title \
  --jq '.[] | select(.title == "chore(agents): commit memories and lessons learned")'

# global group
gh pr list --state open --limit 200 --json number,url,headRefName,title \
  --jq '.[] | select(.title == "chore(global-memories): commit global memories and lessons learned")'
```

Match the group's title exactly in `--jq`, never through `--search`. Set the limit: the default page
is 30, and a standing pull request beyond it would read as "none".

- **None** — a new branch and a new pull request.
- **One** — append to it: use its `headRefName` and open no second pull request.
- **More than one** — do not guess and do not open a third: report the collision in the wrap-up report
  and skip that group. The finish flow does not wait for an answer.
- **Neither `origin/<default>` nor `origin/<headRefName>` resolves after the explicit fetch** — report
  the group and skip it; never revive or guess a base.

Lookup and create are not atomic: two wrap-ups can both see "none". After `gh pr create`, re-list the
group's title; when a second one appeared, report both URLs and leave both open — never close another
session's pull request. The rule is "append when you see one"; a twin created concurrently belongs to
the human.

### 4. Prepare the branch

Everything runs from the repository's main checkout; never switch its checked-out branch.

- **Standing pull request found** — fetch the branch into its remote-tracking ref:
  `git -C "$root" fetch origin "+refs/heads/<headRefName>:refs/remotes/origin/<headRefName>"` (add
  `--depth 1` in a shallow clone). Then cut a **fresh** temporary worktree from
  `origin/<headRefName>`, detached. Never reuse another session's worktree: it may hold dirty or
  staged changes, or a `HEAD` that differs from the fetched tip.
- **No standing pull request** — the default fetch from step 3 already ran; create a branch from
  `origin/<default>`, named for the stream: `chore/commit-memories-<YYYYMMDD-HHMMSS>-<pid>` for a
  vault group, `chore/global-memories-<YYYYMMDD-HHMMSS>-<pid>` for a global group. `<pid>` is the
  shell's `$$`, so two finish flows in the same second cannot collide; a merged or closed branch is
  never revived. If the branch still exists, retry with a fresh nonce.

A failed run's temporary worktree may be reaped while git keeps its registration — `/tmp` is reaped,
the entry is not. Run `git -C "$root" worktree prune` before creating a new one, and never reuse a
vanished path.

Use a temporary linked worktree, not the main checkout:

```bash
wt="$(mktemp -d)/wt"
git -C "$root" worktree add -b "$branch" "$wt" "origin/$default"  # new branch
git -C "$root" worktree add --detach "$wt" "origin/$branch"       # standing branch
```

A detached worktree needs no branch checkout, so a concurrent session's worktree cannot block it and
the commit is pushed to `HEAD:<headRefName>`. The temporary worktree keeps the main checkout
untouched and needs no ignore rule; remove it after the push. Never reuse another session's
worktree — a fresh detached one is safe beside it.

### 5. Commit the notes

Before copying anything, run `git -C "$wt" check-ignore <path>` for each destination path — the probe
works on a path that does not exist yet, and the branch's `.gitignore` decides. A **project-vault**
path that is ignored is skipped. A **global-store** path that is ignored is a defect: the store is
tracked by design, so report it as an error and leave the file out — never drop it silently and never
force-add it. Copy the accepted paths from their main-checkout location to the group's
repository-relative path — a global note uses its `storage/global-memories/...` target resolved in
step 1 — creating directories as needed. Then, in the worktree:

- run the commit protocol's checks over the copied files — `devbot:format-md` for every Markdown note,
  plus the project's lint and tests when they cover the vault;
- stage the exact paths (`git -C "$wt" add -- <paths>`), never a blanket add;
- commit one atomic memory commit with a Conventional Commit (`devbot:git-commits`), for example
  `docs(memory): capture session memories and lessons`.

Nothing staged means nothing to publish: skip the group. Memory commits are ordinary commits,
never fixups: a capture writes new notes, so even a correction to an earlier note is a new ordinary
commit, and the append path's earlier memory commits are never rewritten.

### 6. Publish

The title and body follow `devbot:gh-create-pr`; its finish-flow-publisher exception is what allows
this skill to publish unattended. Push the branch, then open the pull request only when step 3 found
none:

```bash
git -C "$wt" push -u origin "$branch"            # new branch
git -C "$wt" push origin "HEAD:$branch"          # standing branch

gh pr create --repo <owner/name> --base "$default" --head "$branch" \
  --title '<group title>' \
  --body-file <body>
```

Run `gh` from the repository root, or pass `--repo <owner/name>` — resolved with
`gh repo view --json nameWithOwner --jq .nameWithOwner` — as shown. The group's title is fixed: the
standing home for this kind of change, not a summary of the notes. Use
`chore(agents): commit memories and lessons learned` for a vault group and
`chore(global-memories): commit global memories and lessons learned` for a global group. Write the body
to a temporary file in the ordinary Problems/Solutions shape:

```text
Problems:
- session memories stay on a local branch no one reviews
- global lessons accumulate untracked in the toolkit

Solutions:
- publish the vault notes from the project that owns them
- collect them in one reviewable pull request per repository
```

A push that fails leaves the commit in the worktree — on the local branch when the skill created one,
otherwise in the detached `HEAD`. Keep the worktree and make a detached commit reachable by naming it:
`git -C "$wt" branch chore/commit-memories-recovered-<timestamp> HEAD`. Report that branch, the
worktree and the failure, and open no pull request. Never merge, never push the default branch, never
force-push, and never request a review — the pull request's review is the human's.

### 7. Clean up and report

Remove only the temporary worktree this skill created, once its branch is pushed:

```bash
git -C "$root" worktree remove "$wt"
```

A worktree that was already there belongs to its session — leave it. Report one line per group: the
pull request URL, or why the group was skipped. Say when nothing was published: an unchanged vault is
a valid outcome.

## MUST

- Group by the repository and stream that owns each note: project vault → that project; global
  store → dev-bot. Never mix the two streams in one branch or pull request.
- Keep one standing pull request per group, titled exactly the stream's title:
  `chore(agents): commit memories and lessons learned` for a vault group and
  `chore(global-memories): commit global memories and lessons learned` for a global group; append to
  the open one instead of opening a second.
- Publish unattended from the finish flow: no permission prompt, no confirmation round.
- Commit only the capture's memory files, staged explicitly, on a branch — never the default branch.
- Respect `commit_memory` and `git check-ignore` for project-vault notes; the global store needs no
  such gate.
- Report every pull request URL, and every group skipped or left with an unpushed branch.
- Report a standing pull request that carries more than 10 commits, and recommend merging it.

## MUST NOT

- Merge a pull request, force-push, push the default branch, or open a second standing pull request.
- Commit through a symlink, or treat a global note as project-vault content.
- Stage the whole vault, work folders, `thinking/`, or any file the capture did not write.
- Write memory notes: the capture is the only writer, and this skill runs after it.
- Ask a question during the finish flow when the state is ambiguous — report it and stop that
  repository.
