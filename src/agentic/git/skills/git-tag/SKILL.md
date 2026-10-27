---
name: devbot:git-tag
description: "Use when creating a git tag or cutting a git-side release. Triggers on 'create a tag', 'tag this release', 'cut a tag'."
---

# Git Tag

Create an annotated release tag: merge the current branch into the default
branch, fold its fixups, tag it, and push the branch and the tag. Everything
deterministic lives in `tools/tag.sh`; you gather input, gate, and call it.

Publishing the GitHub release for the tag is a **separate** step — see
`devbot:gh-release`. This skill stops once the tag is pushed.

## Never change the VCS before the user approves

Steps 1–3 only read. Do not run `merge`, `tag` or `push` until the user has
approved the plan from step 3 — not even to "check" something first.

## 1. Resolve the version

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" version [--version "$1"]
```

Pass `--version` only when the user supplied one. A `FATAL:` here means the
version is invalid, is already tagged, or the remote has no tags to bump (a
first release needs an explicit version) — tell the user and stop.

## 2. Write the release notes

Load the `devbot:git-changelog` context skill and produce the release file for
that version. It writes `release.v<VERSION>.no-vcs.md` (the version with dots
turned into dashes) at the repo root — the **single source** for the tag
description and the GitHub release notes.

That file is gitignored: never `git add` it, never commit it.

## 3. Present the plan and get approval

List the remotes with `git remote`. **If there is more than one, ask the user
which remotes the tag should be pushed to** before rendering the plan; with a
single remote, use it without asking.

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" plan \
  --version "<version>" --notes-file "release.v<VERSION>.no-vcs.md" \
  --remotes <comma-separated remotes>
```

Show the output **verbatim** — it is the exact plan. Ask for approval or change
requests. A change request (a different version, description, or remotes) means
going back to the relevant step, re-rendering the plan, and asking again.

## Already-merged releases: tag only

When the release commit is already on the remote — the PR is merged, or the
local default branch is ahead or diverged so pushing it would be wrong — do not
merge or push a branch at all. Set `--tag-only` and point `--ref` at the
release commit:

```
# <remote> is the release remote chosen in step 3 and <default> its default
# branch — neither is necessarily `origin` or `main`. Fetch first: the plan
# resolves the remote's tip read-only, and the tag step needs that commit in
# the local object database.
git fetch <remote> <default>

bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" plan --tag-only \
  --version "<version>" --ref <remote>/<default> \
  --notes-file "release.v<VERSION>.no-vcs.md" --remotes <remotes>

# --tag-only takes the immutable SHA the plan printed, never the branch ref:
# origin/main can advance between the approval and this call.
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" tag --tag-only \
  --version "<version>" --ref <sha-from-the-plan> \
  --notes-file "release.v<VERSION>.no-vcs.md"

bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" push --tag-only \
  --version "<version>" --remotes <remotes>
```

The plan then carries no source branch and no merge line, and `push` sends the
tag alone. For the full GitHub release, `devbot:gh-release` drives the same
three commands.

## Never push a protected default branch

Before the merge step, check whether the default branch accepts direct pushes:

```
gh api "repos/<owner>/<repo>/branches/<default>/protection" >/dev/null 2>&1 && echo protected
```

When it is protected — required pull request, required status checks, or any
ruleset that rejects a direct push — **do not merge locally and push**. Land the
release commits through a PR instead:

```
# The branch can gain commits while the PR is open, so the guards are a function
# run before publishing and again immediately before merging.
check_release_guards() {
  git rev-parse --verify --quiet origin/<default> >/dev/null \
    || { echo "ERROR: origin/<default> is unavailable — cannot verify vault commits"; return 1; }

  # Fixups: consume the stream to EOF — under pipefail `grep -q` can SIGPIPE git.
  if git log --format=%s origin/<default>..<source-branch> \
    | awk '/^(fixup|squash|amend)!/ { found=1 } END { exit found ? 0 : 1 }'; then
    echo "ERROR: fold the fixups before merging"
    return 1
  fi

  # Vault commits are ordinary commits, so the subject check cannot see them.
  # `.` is a valid <devbot_dir>: git emits `memory/...`, not `./memory/...`.
  local vault="<devbot_dir>"
  case "$vault" in . | ./) vault="" ;; ./*) vault="${vault#./}" ;; esac
  while [ "${vault%/}" != "$vault" ]; do vault="${vault%/}"; done
  case "$vault" in
    /*) echo "ERROR: absolute <devbot_dir> — refusing to guess the vault path"; return 1 ;;
  esac
  case "/$vault/" in */./* | */../* | *//*) echo "ERROR: non-canonical <devbot_dir> — refusing to guess the vault path"; return 1 ;; esac
  vault="${vault:+${vault}/}memory/"

  # Commit-level path history: a net tree diff misses a vault file added then
  # deleted. Merge commits contribute only their conflict resolutions (`--cc`).
  # Every read is checked — an error piped into awk would look like a clean
  # range. The local default publishes too, when it exists.
  local range merges m paths
  local ranges="origin/<default>..<source-branch>"
  git rev-parse --verify --quiet <default> >/dev/null && ranges="$ranges origin/<default>..<default>"
  for range in $ranges; do
    paths="$(git log --format= --name-only "$range")" \
      || { echo "ERROR: cannot inspect '$range'"; return 1; }
    merges="$(git log --merges --format='%H' "$range")" \
      || { echo "ERROR: cannot inspect '$range'"; return 1; }
    for m in $merges; do
      paths="$paths
$(git -c core.quotePath=false show --cc --name-only --format= "$m")" \
        || { echo "ERROR: cannot inspect merge '$m'"; return 1; }
    done
    # Git C-quotes a control-character path, which the prefix test cannot see.
    if printf '%s\n' "$paths" | grep '^"' >/dev/null; then
      echo "ERROR: git quoted a path in '$range' — refusing to guess"
      return 1
    fi
    if printf '%s\n' "$paths" | VAULT_PREFIX="$vault" awk 'index($0, ENVIRON["VAULT_PREFIX"]) == 1 { found=1 } END { exit found ? 0 : 1 }'; then
      echo "ERROR: memory-vault commits would be published on $range; resolve them first"
      return 1
    fi
  done
}

check_release_guards || exit 1
git push origin <source-branch>
gh pr create --base <default> --head <source-branch> --title "<release title>"

# After review: capture the lease, fold the fixups added since (PR stage,
# devbot:git-fixup-commits), then hand over the leased push. `gh pr merge` uses
# the REMOTE head, so the rewrite is invisible until it is published.
expected="$(git rev-parse origin/<source-branch>)"
# The lease is only safe when the checkout already matches that head; anything
# else means the source moved and must be reconciled first.
[ "$(git rev-parse HEAD)" = "$expected" ] \
  || { echo "ERROR: local <source-branch> does not match origin — reconcile before rewriting"; exit 1; }
# ... run the PR-stage squash ...
# hand this to the human:
git push --force-with-lease=refs/heads/<source-branch>:$expected origin <source-branch>
# Verify the handoff landed, then only once that push has landed:
git fetch origin <source-branch>
[ "$(git rev-parse origin/<source-branch>)" = "$(git rev-parse HEAD)" ] \
  || { echo "ERROR: the leased push did not land — remote and local still differ"; exit 1; }
check_release_guards || exit 1
gh pr merge <pr> --rebase        # or --squash, per the repo's convention

# The PR merge advanced only the remote: bring the local default up before
# tagging, or `tag` would tag the stale pre-merge checkout.
git fetch origin <default>
git switch <default>
git merge --ff-only origin/<default>
```

`tag.sh merge` runs both checks itself and refuses with `FATAL:` instead of publishing a fixup or a
vault commit.

**On this protected path the PR merge replaces the local merge.** Do not run `tag.sh merge`
afterwards: the remote tip is no longer an ancestor of the updated default branch (and a deleted
source branch cannot be merged at all), so a local merge would reintroduce commits that already
landed. Continue with `tag` and `push` only.

Wait for the required checks, then run `tag` and `push`. The default branch is
already in sync at that point, so `push` sends only the tag.

`tag.sh push` refuses to move a protected branch and prints this same
remediation — treat that refusal as the correct outcome, not an obstacle to
work around. A push that reports `Bypassed rule violations` is a failure: the
work has to go back through a PR.

## 4. On approval, run the tag in order

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" merge   [--source "<branch>"] [--default "<default branch>"]
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" tag     --version "<version>" --notes-file "<notes file>"
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" push    --version "<version>" --branch "<default branch>" --remotes <remotes>
```

Run them one at a time, in that order, and report each step's outcome.

- **`merge`** folds every `fixup!`/`squash!`/`amend!` commit not yet on the
  default branch into its target, then merges the branch you were on into the
  default branch and switches to it. On a conflict it aborts, restores your
  original branch, and exits `FATAL:` — stop there, nothing was tagged.
- **`tag`** creates the annotated tag, its description being the notes file
  verbatim.
- **`push`** pushes the default branch and the tag to each remote. A failing
  remote does not stop the others; report which failed and the remediation the
  script printed.

The checkout is left on the default branch; do not switch back.

## Notes

- `$DEV_BOT_ROOT` is exported by the harness. If it is unset, fall back to the
  script inside the dev-bot checkout.
- Close by reporting plainly: which branch was merged, the tag name, and every
  remote the tag reached.
