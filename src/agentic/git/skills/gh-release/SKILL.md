---
name: devbot:gh-release
description: "Use when making or publishing a GitHub release. Triggers on 'make a release', 'create a release', 'publish the release'."
---

# GitHub Release

Make a release. This is the **full-release entry point**: it performs the git
half — merge, tag, push — and then publishes the GitHub release, so a user
asking to "make a release" needs nothing else.

The git half **is** the `devbot:git-tag` skill; follow it, but gate once over a
combined preview (step 3) instead of the tag skill's own gate. Everything
deterministic lives in `tools/tag.sh` (git) and `tools/release.sh` (GitHub);
you gather input, gate, and call them.

## Never change the VCS before the user approves

Steps 1–3 only read. Do not run `merge`, `tag`, `push` or `release` until the
user has approved the combined preview from step 3.

## 1. Resolve the version and write the notes

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" version [--version "$1"]
```

Pass `--version` only when the user supplied one. A `FATAL:` here means the
version is invalid, already tagged, or the remote has no tags to bump — tell the
user and stop.

Then load the `devbot:git-changelog` context skill and produce
`release.v<VERSION>.no-vcs.md` (dots turned into dashes) at the repo root — the
**single source** for the tag description and the GitHub release notes. It is
gitignored: never `git add` it, never commit it.

## 2. Choose the remotes

List the remotes with `git remote`. **If there is more than one, ask the user
which the release should go to** before rendering the preview; with a single
remote, use it without asking.

## 3. Present one combined preview and get one approval

Render both halves — the git steps and the GitHub step — as a single preview:

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" plan \
  --version "<version>" --notes-file "release.v<VERSION>.no-vcs.md" \
  --remotes <comma-separated remotes>
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" plan \
  --version "<version>" --remotes <comma-separated remotes>
```

Show both outputs **verbatim**, tag plan first, and ask for a **single**
approval. A change request means going back, re-rendering both, and asking
again.

**When the tag is already pushed** — the git half is done — show only the
`release.sh plan` output and, on approval, run only the `release` step of step 4.

## 4. On approval, run in order

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" merge   [--source "<branch>"] [--default "<default branch>"]
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" tag     --version "<version>" --notes-file "<notes file>"
bash "$DEV_BOT_ROOT/src/agentic/git/tools/tag.sh" push    --version "<version>" --branch "<default branch>" --remotes <remotes>
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" release \
  --version "<version>" --notes-file "<notes file>" --remotes <remotes>
```

Run them one at a time, in that order, and report each step's outcome.

- **`merge`** folds every `fixup!`/`squash!`/`amend!` commit into its target,
  then merges the branch into the default branch. On a conflict it aborts,
  restores your branch, and exits `FATAL:` — stop there; nothing was tagged.
- **`tag`** creates the annotated tag from the notes file.
- **`push`** pushes the default branch and the tag to each remote; a failing
  remote does not stop the others.
- **`release`** publishes a GitHub release per release-capable remote. It
  degrades to a `WARN:` when `gh` is absent or unauthenticated — the tag push
  still stands.

The checkout is left on the default branch; do not switch back.

## Notes

- `$DEV_BOT_ROOT` is exported by the harness. If it is unset, fall back to the
  scripts inside the dev-bot checkout.
- Close by reporting plainly: which branch was merged, the tag name, every
  remote the tag reached, and every release created.
