---
name: devbot:git-fixup-commits
description: "Use when correcting a commit unique to the branch. Triggers on 'fixup', 'squash this into', 'autosquash', 'amend an earlier commit'."
---

# Fixup Commits

When a change corrects a commit that is unique to the current branch, record it as a fixup against that commit instead of adding a loose "fix typo" commit. The eventual history stays atomic, and the rewrite stays a separate, deliberate step the agent performs itself.

The core distinction: **creating a fixup commit is always safe** — it only adds a commit. **Squashing it rewrites history** — it does not.

## Branch scope (MUST)

The deciding question is whether the **target commit is unique to this branch** — not whether it has
been pushed. A target is unique when it is reachable from neither the default branch nor any other
branch.

- **Target commit is unique to this branch** (a feature branch, including one with an open pull request) — the correction MUST be recorded as a fixup against that commit. This is the default workflow, not an option, and it applies to pushed commits too: creating a fixup only _adds_ a commit, so it is safe at any point in the branch's life. Only the later squash rewrites anything.
- **Target commit is reachable from the default branch** (`main`, `master`, …), or from another branch — never record a fixup. That history is shared; a correction there is a normal follow-up commit.
- **Before merging** — fixup commits MUST be squashed into their targets first; they must never reach the default branch. Projects commonly enforce this with a CI check that fails a PR whose branch still contains fixup!/squash!/amend! commits, so an unsquashed fixup is expected to fail that check until it is folded in. See [PR stage](#pr-stage).
- **Squashing needs no permission (MUST NOT)** — never ask the user whether to squash a branch's own fixups, and never present the squash as theirs to approve. Every commit in the rewrite range is unique to this branch (proven above), the plan is printed as a record, and the guards module blocks the force-push — so the rewrite is safe to run and the publish still waits for the human. Asking turns a routine step into a decision it is not.

## Choose the right action first

| Situation                                                        | Action                                                                  |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Correction to a commit unique to this branch (pushed or not)     | `git commit --fixup=<sha>`                                              |
| The target commit is itself a fixup                              | Target the commit it fixes — never create fixup! fixup!                 |
| Correction to a commit already reachable from the default branch | Normal follow-up commit — fixups are forbidden there                    |
| Branch under review with per-commit comments                     | The fixup is still right; squash it when the flow calls for it          |
| Memory/global note lives in another repository                   | Commit in the repository that owns the note; a fixup has no target here |

## Workflow

### 1. Identify the target commit

```bash
# Remember the remote head before refreshing: a fetch hides a deletion or a
# force-reset to an ancestor.
before=""
git rev-parse --verify --quiet origin/<branch> >/dev/null && before="$(git rev-parse origin/<branch>)"
git fetch --all --prune                     # every remote the containment check reads
after="$(git rev-parse --verify --quiet origin/<branch> 2>/dev/null || true)"
if [[ "${before}" != "${after}" ]]; then
  echo "origin/<branch> changed (${before:-absent} -> ${after:-absent}) — stop and reconcile"
  exit 1
fi
git log --oneline origin/<default>..HEAD     # the rewrite range — every commit the squash replays
range="$(git rev-list origin/<default>..HEAD)" || { echo "cannot list the rewrite range — stop"; exit 1; }
current="$(git branch --show-current)"       # this branch and its own origin/<current> are expected
shared=""
while read -r sha; do
  # Enumerating refs failing is not "no sibling": it stops the flow.
  refs="$(git for-each-ref --contains="$sha" --format='%(refname)' refs/heads refs/remotes)" \
    || { echo "cannot enumerate refs for ${sha} — stop"; exit 1; }
  # Only grep's status 1 is expected here: it means no sibling.
  siblings="$(printf '%s\n' "${refs}" | grep -vxF \
    -e "refs/heads/${current}" -e "refs/remotes/origin/${current}" || true)"
  [ -z "${siblings}" ] || shared="${shared}${sha} ${siblings}"$'\n'
done <<< "${range}"
[[ -z "${shared}" ]] || { echo "shared commits in the rewrite range: ${shared}"; exit 1; }
if git rev-parse --verify --quiet origin/<branch> >/dev/null; then
  git rev-list --count HEAD..origin/<branch>   # > 0: you are behind
fi
git log --oneline -10
git blame -L <start>,<end> -- path/to/file   # which commit introduced these lines
git log -S '<changed string>' --oneline      # commits that added/removed a string
git log --oneline -G '<regex>'               # commits whose diff matches a pattern
```

Target the commit that _introduced_ the thing being corrected, not merely a later commit that touched the same file. `git blame` on the pre-correction version of the line is the most reliable signal. Confirm with `git show --stat <target-sha>`.

The range only decides what to look at; it proves nothing. Fetch **every** remote first (`--all`) — containment reads all `refs/remotes`, so refreshing only `origin` leaves a sibling on another remote stale, and a shared commit looks unique. Then prove the **whole rewrite range** is this branch's alone: step 6 replays every commit in `origin/<default>..HEAD`, so a unique target is not enough — an earlier commit in that range can still be reachable from a sibling branch (`release`, another worktree's branch), and the squash would replay it and publish a rewritten copy. The check above lists every ref holding each commit in the range, so exclude the current branch and its own remote-tracking ref by exact ref name (fixed-string matching, so a branch called `feature/foo+bar` is not misread as a regex). Anything left is a sibling: stop. Capture the filtered result rather than piping it straight into the shell — no sibling is the normal case, and `grep`'s exit 1 there must not abort a `set -e` workflow.

A remote head that changed during the fetch stops the workflow: a branch that moved on (or was rewritten), a ref that vanished, or one that appeared — each means your checkout no longer matches the PR, and a lease captured afterwards would make the rewrite overwrite it. Stop and reconcile before creating a fixup. The `HEAD..origin/<branch>` count alone cannot see a force-reset to an ancestor or a deleted ref, which is why the head is captured before the fetch and compared after.

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

### 4. Keep the fixup until the flow calls for the squash

A branch may legitimately carry fixups for a while: the commit records "this belongs to that commit" without destroying anything, which is the right state mid-review. Squash when the flow reaches that point — the pre-merge step of [PR stage](#pr-stage), or a branch about to be pushed — not merely because a fixup exists. When it does, squash it yourself; do not hand the decision back.

### 5. Capture the lease, then print the plan

Capture the expected remote head **before** any rewrite. Step 1 refreshed every origin ref; from here on,
refresh only the base — fetching `<branch>` would adopt a colleague's newer tip as the lease:

```bash
# Only a published branch has a remote head to lease.
git rev-parse --verify --quiet origin/<branch> >/dev/null \
  && git rev-parse origin/<branch>     # expected head — save it; the publish needs it
git fetch origin <default>        # refresh the base only, never <branch>

git log --oneline origin/<default>..HEAD    # the commits to be rewritten

# Print the exact autosquash plan without executing it: the editor prints the
# todo list then fails, so the rebase aborts untouched. Capture the plan and
# require it: a failure before the editor, or a rebase that ran, stops here.
head_before="$(git rev-parse HEAD)"
plan="$(GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' \
  git rebase -i --autosquash origin/<default> 2>/dev/null)" && {
  echo "preview applied a rebase — stop"
  exit 1
}
[ -n "${plan}" ] || { echo "preview printed no plan — stop"; exit 1; }
[ "${head_before}" = "$(git rev-parse HEAD)" ] || { echo "preview moved HEAD — stop"; exit 1; }
printf '%s\n' "${plan}"
```

That prints the `pick`/`fixup` lines showing precisely which commit folds into which, exits non-zero, and leaves history unchanged. There is no `git rebase --dry-run`; this is the substitute. Capturing the output is what proves the plan was printed: an empty capture or a successful rebase stops the flow before anything is rewritten. (Using bare `cat` here hangs — it reads stdin — so keep the `"$1"`.)

State the base, how many commits are affected, which fixups fold into which targets, and whether any of them have been pushed. When the branch is published, include the exact leased push command from step 7.

**Then apply it — do not ask.** Squashing a branch's own fixups is a routine step of the flow, not a decision to escalate. Every commit in the rewrite range is unique to this branch (step 1 proved it) and the guards module blocks the force-push, so nothing reaches shared history without the human. The plan is printed as a record of what the rewrite touches, never as a request for approval. The push remains the human's to run — see step 7.

### 6. Apply the squash

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<default>
```

`GIT_SEQUENCE_EDITOR=:` replaces the todo-list editor with a no-op (`:` is a shell builtin that succeeds silently), accepting the pre-arranged list without opening an editor. This is safe _only because_ step 1 proved every commit in the rewrite range is unique to this branch and step 5 printed the plan — never combine it with a rebase whose range is not proven unique.

### 7. Hand the publish to the human

Do not force-push. The guards module denies every force-push form, including `--force-with-lease`, on
every shell channel — it is deny-only by design, and the publish stays the human's decision.

Hand over the command with the sha captured in step 5:

```bash
git push --force-with-lease=<branch>:<expected-sha> origin <new-head>:<branch>
```

`--force-with-lease=<branch>:<expected-sha>` refuses the push unless the remote branch still points
at `<expected-sha>`. The key must be the **short** branch name, identical to the refspec
destination: a fully-qualified `refs/heads/<branch>` key can end up not associated with the pushed
ref, and git then runs the push unforced — reported as a plain `non-fast-forward` rejection. The
bare form compares against the local remote-tracking ref instead, so fetching `<branch>` first would
adopt a colleague's new tip as the expected value and overwrite it silently — never fetch `<branch>`
between capturing the sha and the push, and never use bare `--force`. Tell the
human the new head and the pull request's URL; its checks re-run when they push.

A branch that has never been pushed has no `origin/<branch>` and no lease to capture: the human
publishes it after the squash with an ordinary `git push -u origin <branch>`.

### 8. Never rewrite shared history outside this flow

Creating a fixup is not rewriting, and squashing a branch that is yours alone — including its open
pull request — is the flow above; neither needs approval. Everything else is the check in
`devbot:git-commits` under **Rewriting history (MUST)**: run it before touching history, and state
plainly whether any target has been pushed. When that check fails, the rewrite is not done at all —
it is not "done after asking"; a correction on shared history is a normal follow-up commit.

## PR stage

While a pull request is open, the branch keeps its history: every correction to the branch's own
commits is a fixup, never a new `fix(...)` commit. The reviewer reads the branch as it evolves, and
the squash is what makes the final history atomic.

Just before merge:

1. **Capture and fetch** — `git rev-parse origin/<branch>` records the lease, then `git fetch origin <default>` refreshes the base. Never fetch `<branch>` itself: that would move the lease onto a colleague's tip.
2. **Re-prove, then squash** — fixups added since step 1 extend the rewrite range, so re-run step 1's range check against the current tip before rewriting; then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<default>`, per steps 5–6 (plan printed, no approval needed). Base on **`origin/<default>`, never the local `<default>`**: the local default may carry stranded commits, and rebasing onto it would make them ancestors of the branch and publish them with the rewrite.
3. **Confirm** — nothing folded short of its target, and list any vault files in the range:

   ```bash
   git log --oneline origin/<default>..HEAD                                     # no fixup!/squash!/amend! subjects
   git log -m --format= --name-only origin/<default>..HEAD -- <vault-path>      # vault files: decide with the human
   ```

   `<vault-path>` is `<devbot_dir>/memory` — or plain `memory/` when `<devbot_dir>` is `.`. Vault commits are ordinary commits, so the subject check cannot see them. Anything listed publishes with the branch — confirm the human wants that before merging.

4. **Publish** — hand `git push --force-with-lease=<branch>:<expected-sha> origin <new-head>:<branch>` to the human (step 7).

Do not merge the pull request while fixup subjects are still on the branch.

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
git rebase -i --autosquash origin/<default>  # everything unique to the branch — usually right
git rebase -i --autosquash <target-sha>^     # tightest base when fixing one commit
git rebase -i --autosquash --root            # entire history — rarely wanted
```

Prefer `origin/<default>` over the local `<default>`: the local branch may carry unpushed commits, and using it as the base pulls them into the rewrite.

`<target-sha>^` fails on a root commit, where `--root` is needed. Add `--autostash` if the user has uncommitted work to preserve across the rebase.

## Autosquash matching

`--autosquash` reorders the todo list so each fixup!/squash!/amend! commit sits directly after its target, marked to fold in. It matches on the commit _subject line_, or on the sha recorded when `--fixup=<sha>` was used. Two consequences:

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

- **The commit is already reachable from the default branch or another branch** → normal follow-up commit
- **A memory-vault commit** → an ordinary commit containing only the memory files, on the memory pull request's branch (`devbot:commit-memories`); never a fixup on a task branch
- **The change is not a correction to code this branch introduced, but new independent behaviour** → a new atomic commit, not a fixup
- **The target is the most recent commit with nothing stacked on it** → `git commit --amend` is simpler
- **The branch is under review with per-commit comments** → the fixup is still right; squash it when the flow calls for it
