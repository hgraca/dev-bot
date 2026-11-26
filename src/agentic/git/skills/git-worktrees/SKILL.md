---
name: devbot:git-worktrees
description: "Under the `worktrees` workflow (the default): use when you are about to make changes you will commit and are not already inside a linked git worktree — before editing, isolate the work in a worktree under <devbot_dir>/worktrees/, so the main checkout stays untouched."
---

# Git Worktrees

Under the `worktrees` workflow every commit is made from a **linked worktree**, never from the main
checkout. The finish flow's memory publishing is no exception to the branch rule: `devbot:commit-memories`
copies the capture's vault notes into a temporary linked worktree, commits them on a memory branch, and
opens or appends that branch's standing pull request. This keeps the
main checkout's checked-out branch untouched, and gives each task an isolated branch cut from the
**remote** default branch. This is the `worktrees` workflow, the default; a project selects
another workflow with the `workflow` key (see [Opting out](#opting-out)).

## Before editing (MUST)

### No silent exceptions

A worktree commit is inert for the running session when the changed files are harness-consumed
tooling: skills, commands, MCP launchers/config, hooks — everything the harness reads through
symlinks into the main checkout. If you believe a worktree commit will not take effect, **stop and
ask** — do not silently work in the main checkout. The two sanctioned options are:

- **(a) worktree commit** — the change takes effect after merge or checkout; say so in the hand-back.
- **(b) main-checkout commit, user-approved** — only with the user's explicit go-ahead: work on the
  **current branch** (never the default branch unless explicitly requested by the user), stage only
  your files and commit with a pathspec, and never push.

State the chosen option in the hand-back so the trade-off stays visible.

### Polyrepo sessions

In a polyrepo project, resolve the owning project of the files in play first — a
polyrepo is a container for sibling repositories, not a codebase, so `create` refuses it even
when it has commits. Carry the owner through every command in this skill with one variable; the
worktree then lands under the **owner's** `<devbot_dir>/worktrees/` and the owner's `workflow`
setting decides whether it applies:

```bash
project=(--project "$(devbot tool where <file> | jq -r .path)")
```

In a normal project the variable stays empty and the commands run as written:

```bash
project=()
```

Every subcommand that needs a repository takes that array — `create`, `enabled`, `list`, `path`,
`push` and `remove` — so a polyrepo session acts on a child while running from its own root.
`create` and `enabled` refuse the polyrepo root itself; the rest would silently resolve the
polyrepo's repository, so always carry `--project`. `<branch>` is the branch name, never the
worktree directory name. Running the tool with the child's main checkout as the working directory
works too, but `--project` does not depend on the shell's location.

Then check the workflow in use — exit `0` means the `worktrees` workflow applies; exit `1` means the
project selected another workflow (see [Opting out](#opting-out)), so work and commit in the **owning
project's** main checkout as that workflow directs (in a polyrepo session that is `git -C
"$owner"`, never the session root); exit `2` means the configured workflow is unknown — **stop and
ask**, never guess. This policy does not apply outside `worktrees`:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" enabled "${project[@]}"
```

When the `worktrees` workflow is in use, detect where you are:

```bash
git rev-parse --git-dir --git-common-dir
```

- **Two different paths** — you are already in a linked worktree. Work and commit here; this
  policy is satisfied.
- **The same path** — you are in the main checkout. Create a worktree **before the first edit**:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create <branch> "${project[@]}"
```

`<branch>` is a descriptive name for the task — `feat/add-login`, `fix/null-token`. The tool:

- fetches `origin` and bases the new branch on `origin/<default>` — never on the main checkout's
  current branch, and never with an upstream (`--no-track`);
- puts the worktree at `<devbot_dir>/worktrees/<slug>` (default `.agents/worktrees/`), keeps that
  directory out of `git status`, and prints the absolute path;
- hard-links `vendor/` and `node_modules/` from the main checkout into the new worktree — override
  with `--link <dir>` (repeatable) for other ecosystems, or skip with `--no-link` (see
  [Dependencies](#dependencies));
- warns but proceeds if the main checkout is dirty.

The main checkout's branch is never switched. The tool fails if the branch or worktree path
already exists.

Nothing in this flow depends on the main checkout's branch or its local state: the worktree is cut
from `origin/<default>`, the commits live on the worktree branch, and finishing pushes that branch
and opens a pull request. Leave the main checkout wherever it happens to be.

## Work in the worktree

The worktree is a separate checkout: **all edits use absolute paths under the printed worktree
path**, and **all git commands run with `-C <worktree>`**. It has no `.agents/` runtime farm —
skills, tools, and memory are served from the main checkout.

```bash
W="$(bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create feat/add-login "${project[@]}")"
# edit "$W/src/..."
git -C "$W" add src/...
git -C "$W" commit -m "feat: add login"
```

Commit exactly as `devbot:git-commits` and `devbot:git-atomic-commits` describe — the commits just
land on the worktree branch.

## Worktree preflight

If the project's Makefile provides them, boot the worktree with its own targets:

- `make up-worktree` — starts the shared stack from the main checkout, then boots this worktree.
  `make up` is the main-checkout path and refuses inside a worktree.
- `make bootstrap-phpunit` — creates and migrates the `_phpunit` database that `make t` and
  `make unit` need.
- `make test-bats` — runs the bats suite with `BATS_LIB_PATH` pointed at the global npm root,
  installing `bats-assert`/`bats-support` there if missing. Raw `bats` cannot find those libs.

When the project defines neither, use its own documented boot and test targets.

`worktree.sh create` copies `storage/cache/static_analysis` from the main checkout, and
`worktree.sh remove` copies it back, so static analysis starts warm.

In a project whose PHP language server roots at the main checkout, `.agents/worktrees/**` is excluded
from its index; use that project's static-analysis and test targets as the authoritative check for
worktree code.

### Resolve the path, never rebuild it

The directory is the branch's **slug**, not the branch name — `feat/add-login` lives in
`feat-add-login/`. A path assembled from the branch name points at nothing, and the resulting
`fatal: cannot change to '…': No such file or directory` reads like a worktree that vanished.

Ask the tool instead — it reads git's own registration, so it also finds a worktree someone placed
elsewhere:

```bash
W="$(bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" path feat/add-login "${project[@]}")"
```

`create` prints the same path for the worktree it just made, `list` shows every worktree under
`<devbot_dir>/worktrees/`, and `push`/`remove` take the registered path from the same lookup. Never
retype a path from memory, never derive it from the branch name, and never hand a branch-shaped
path to a human to run.

Two more ways the same error is produced:

- a **relative destination** passed to `git -C <repo> worktree add` is resolved from inside `<repo>`,
  so a path already carrying the repo prefix — `repo/.agents/worktrees/x` — nests into
  `repo/repo/.agents/worktrees/x`. Always pass an absolute path.
- `git worktree remove <relative path>` fails with `is not a working tree` while the worktree is
  still registered. Pass the absolute path, or use `worktree.sh remove <branch> "${project[@]}"`.

`create` verifies the new worktree is readable before it returns, retrying briefly. Worktree
directories have been observed unreadable for a short window on some filesystems (ecryptfs home
directories among them), and that window was reported as the worktree vanishing; if it persists,
`create` fails naming the branch and the command that resolves it, instead of printing a path
nothing can use.

## Dependencies

A fresh worktree contains only tracked files, so gitignored dependency dirs are absent. `create`
hard-links `vendor/` and `node_modules/` from the main checkout into the worktree, so builds and
tests run without re-installing them. Name the dirs explicitly for another ecosystem:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create feat/x "${project[@]}" --link .venv              # .venv only
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create feat/x "${project[@]}" --link libs --link build  # several
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create feat/x "${project[@]}" --no-link                 # none
```

Any `--link` replaces the defaults (`vendor`, `node_modules`). Linking is best-effort: a missing
source dir, a dir already present in the worktree, or a failed copy warns and continues — the
worktree stays usable, and you can install dependencies there yourself.

Linked files share inodes with the main checkout: a build that **writes** into a dependency dir in
the worktree also mutates the main checkout's copy. Treat linked deps as read-only; pass `--no-link`
and install in the worktree when a tool must write there.

## Running builds and tests

Run builds, tests, and other project commands **from the worktree root**, through the project's
containerised runner (e.g. its `make` targets) — not against the main checkout's container.
Container tooling that scopes its compose project to the working directory already isolates each
worktree, so parallel agents get their own container, volumes, and test run; where the project does
not, give the runner a worktree-scoped project or container name. Compose scoping covers container,
network, and volume **names** — not published host ports, which stay host-global: a fixed host-port
mapping collides when two worktrees start that service, so worktree-scope the ports or avoid
starting host-port-bound services per worktree.

## Finish

Finishing means pushing the worktree branch and opening a pull request — nothing is merged, checked
out, or otherwise changed locally:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" push <branch> "${project[@]}"   # push + set upstream
```

Then open the PR against `<default>` with `devbot:gh-create-pr`, and report its URL. `push` only
pushes the worktree branch to `origin` and sets its upstream; it does not touch the main checkout, so
the whole flow is independent of the local situation.

### Squash fixups before merge

Corrections made while the pull request is open are fixups against the branch's own commits. They
must not reach the default branch, so squash them just before merge (steps 1 and 5–6 of
`devbot:git-fixup-commits`: prove the range is unique, print the plan, then apply it — no approval is
asked):

```bash
# Remember the remote head before refreshing: a fetch hides a force-reset or deletion.
before=""
git -C <worktree> rev-parse --verify --quiet origin/<branch> >/dev/null \
  && before="$(git -C <worktree> rev-parse origin/<branch>)"
git -C <worktree> fetch --all --prune
after="$(git -C <worktree> rev-parse --verify --quiet origin/<branch> 2>/dev/null || true)"
[ "$before" = "$after" ] || { echo "origin/<branch> changed — reconcile before squashing"; exit 1; }
if [ -n "$after" ]; then
  [ "$(git -C <worktree> rev-list --count HEAD..origin/<branch>)" -eq 0 ] \
    || { echo "origin/<branch> is ahead — reconcile before squashing"; exit 1; }
fi
# Prove the WHOLE rewrite range is this branch's alone — the squash replays
# every commit in it, not only the fixup target.
current="$(git -C <worktree> branch --show-current)"
range="$(git -C <worktree> rev-list origin/<default>..HEAD)" \
  || { echo "cannot list the rewrite range — stop"; exit 1; }
shared=""
while read -r sha; do
  # Enumerating refs failing is not "no sibling": it stops the flow.
  refs="$(git -C <worktree> for-each-ref --contains="$sha" --format='%(refname)' refs/heads refs/remotes)" \
    || { echo "cannot enumerate refs for ${sha} — stop"; exit 1; }
  # Only grep's status 1 is expected here: it means no sibling.
  siblings="$(printf '%s\n' "${refs}" | grep -vxF \
    -e "refs/heads/${current}" -e "refs/remotes/origin/${current}" || true)"
  [ -z "${siblings}" ] || shared="${shared}${sha} ${siblings}"$'\n'
done <<< "${range}"
[ -z "$shared" ] || { echo "shared commits in the rewrite range: $shared — stop"; exit 1; }
expected_sha="$after"                            # the lease the handoff uses
# Print the plan (the editor fails, so the rebase aborts untouched), then apply it.
head_before="$(git -C <worktree> rev-parse HEAD)"
plan="$(GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git -C <worktree> rebase -i --autosquash origin/<default> 2>/dev/null)" && {
  echo "preview applied a rebase — stop"
  exit 1
}
[ -n "${plan}" ] || { echo "preview printed no plan — stop"; exit 1; }
[ "$head_before" = "$(git -C <worktree> rev-parse HEAD)" ] \
  || { echo "preview moved HEAD — stop"; exit 1; }
printf '%s\n' "${plan}"
GIT_SEQUENCE_EDITOR=: git -C <worktree> rebase -i --autosquash origin/<default>
# hand this to the human — the agent cannot force-push
head_sha="$(git -C <worktree> rev-parse HEAD)"
git -C <worktree> push --force-with-lease=<branch>:<expected-sha> origin "$head_sha:<branch>"
```

The lease key is the **short** branch name, identical to the refspec destination; a fully-qualified
`refs/heads/<branch>` key can end up not associated with the pushed ref, and git then runs the push
unforced — the human sees a plain `non-fast-forward` rejection instead of the rewrite landing. Pass
the new head as a sha so the refspec cannot resolve to a different local ref either.

On a branch that has never been pushed there is no lease: the human publishes it with an ordinary
`git -C <worktree> push -u origin <branch>` after the squash. A checkout behind `origin/<branch>`
stops before the lease is captured — another checkout pushed commits this one never incorporated.

Base on **`origin/<default>`, never the local default**: local may hold stranded commits, and
rebasing onto it would make them ancestors and publish them. The first rebase prints the plan and
aborts — its sequence editor exits non-zero — so the rewrite is never blind; `GIT_SEQUENCE_EDITOR=:`
then applies that exact plan, because agents have no editor to drive it. Do **not** fetch `<branch>` before
the push — that would adopt a colleague's new tip as the lease and overwrite it; fetch only
`<default>`. The agent prepares the push and hands it over — the guards module denies force-push. See
steps 5–7 of `devbot:git-fixup-commits`.

**Keep the worktree while the pull request is open.** Review feedback is fixed in it, on the same
branch — removing it early strands the follow-up work. Remove it only once the user states the work
is finished **and** the branch is landed — the pull request `MERGED`, or, with no pull request, the
branch an ancestor of `origin/<default>`:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" remove <branch> "${project[@]}"  # removes the dir; keeps the branch ref
git -C <root> branch -D <branch>   # a squash-merge is not ancestry, so -d refuses
```

`remove` refuses a worktree with uncommitted changes, and neither command discards work — anything
unpushed stays where it is and is reported instead. The finish flow performs this teardown:
`devbot:reconcile-work` step 1 walks every worktree and applies exactly this rule, so a wrap-up does
not leave a landed worktree behind.

The finish flow's memory capture (`devbot:remember-session`) writes vault notes in the main checkout;
`devbot:commit-memories` then copies the capture's files into a **temporary linked worktree**, commits
them as **normal commits** (never fixups) on a memory branch, and opens or appends the standing pull
request titled `chore(agents): commit memories and lessons learned`. The main checkout's checked-out
branch is never switched, and the task's pull request carries only its work commits — never memory.

Memory branches are not task worktrees: the temporary worktree is removed after the push, and the
standing pull request is the notes' home until it is merged. Never put vault commits on a task branch,
and never base a task branch on the local default to pick up stranded commits: `create` bases new
branches on `origin/<default>`, so a stranded local commit does not ride along automatically. When you
find one, say so and name it, then let the user decide how it reaches origin. Do not reset, rebase, or
push it, and do not widen a new worktree's base to carry it on your own.

### Drop the worktree's databases

`remove` deletes the directory only. Where a project isolates databases per worktree — a
dev-tools consumer rewrites `.env` to the worktree slug (`<slug>` and `<slug>_phpunit`) on a
**shared** database server — those databases survive the worktree and accumulate. Drop them in
the same cleanup, **before** `remove`, reading the project's own convention (`Makefile.proj.mk`
`init-php` and its compose file) for the exact names and server. For a dev-tools project the
databases live on the shared MariaDB/Mongo:

```bash
# MariaDB
docker exec shared-db-1 mariadb -uroot -ptest \
  -e 'DROP DATABASE IF EXISTS `<slug>`; DROP DATABASE IF EXISTS `<slug>_phpunit`;'
# MongoDB — the convention rewrites DB_MONGO_DATABASE to the same slug.
# mongosh has no `-e`: the eval flag is `--eval`.
docker exec shared-mongo-1 mongosh --quiet \
  --eval 'db.getSiblingDB("<slug>").dropDatabase(); db.getSiblingDB("<slug>_phpunit").dropDatabase();'
```

### Remove the worktree's hosts entries

A worktree's `init-hosts` also added its hosts to the hosts file — `<dir>.<base>.get-e.local`
plus any project-specific ones — and they linger after `remove`. Remove them in the same
cleanup. `host-requirements/run.sh` (run by `make up`) keeps the hosts file writable, so the
project's helper does it without elevation:

```bash
scripts/ensure-hosts.sh --remove <the hosts the project's init-hosts adds>
```

Read the project's `Makefile.proj.mk` `init-hosts` for the exact names — the same literals the
recipe adds, with `${WORKTREE_PREFIX}` (the worktree directory and a dot) in front.

## Opting out

The `worktrees` workflow is the project default. A project (or the global config) selects another
workflow with:

```jsonc
// .devbot.project.jsonc
{ "workflow": "trunk" }
```

Agents then follow that workflow — `trunk` edits and commits on the default branch — and
`worktree.sh create` refuses with a `FATAL:` — raw `git worktree` is still available to a human who
wants one anyway.

## See also

- `devbot:git-commits` — message craft and the history-rewrite safety rule
- `devbot:git-atomic-commits` — grouping, ordering, and branch creation
