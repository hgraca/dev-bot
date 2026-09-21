---
name: devbot:release
description: Cut a release — merge to the default branch, tag it, push to the remotes, and publish the GitHub releases, after showing you the plan
---

Cut a release of this project. Everything deterministic lives in a shell script; you orchestrate
it and gate it:

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" <subcommand> [options]
```

The optional argument (`$1`) is the version to release, e.g. `1.6.0` or `1.6`. When it is absent,
the version is the next minor after the newest tag on the remote.

## Never change the VCS before the user approves

Steps 1–3 only read. Do not run `merge`, `tag`, `push` or `release` until the user has approved the
plan from step 3 — not even to "check" something first.

## 1. Resolve the version

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" version [--version "$1"]
```

Pass `--version` only when the user supplied an argument. A `FATAL:` here means the version is
invalid, is already tagged, or the remote has no tags to bump (a first release needs an explicit
version) — tell the user and stop.

## 2. Write the release notes

Load the `devbot:git-changelog` context skill and produce the release file for that version. It
writes `release.v<MAJOR>-<MINOR>-<PATCH>.no-vcs.md` at the repo root.

That file is the **single source** for both the tag description and the GitHub release notes, so
pass its path to every later step. It is gitignored: never `git add` it, never commit it.

## 3. Present the plan and get approval

List the configured remotes with `git remote`. **If there is more than one, ask the user which
remotes the release should go to** before rendering the plan; with a single remote, use it without
asking.

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" plan \
  --version "<version>" --notes-file "release.v<MAJOR>-<MINOR>-<PATCH>.no-vcs.md" \
  --remotes <comma-separated remotes>
```

Show the output **verbatim** — it is the exact plan, including the tag name, the fixups it will
squash, and the full tag description. Ask for approval or change requests. A change request (a different version, a different
description, other remotes) means going back to the relevant step, re-rendering the plan, and asking
again.

The preview ends with `_No VCS change has been made yet._` — that stays true until the user says yes.

## 4. On approval, run the release in order

```
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" merge   [--source "<branch>"] [--default "<default branch>"]
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" tag     --version "<version>" --notes-file "<notes file>"
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" push    --version "<version>" --branch "<default branch>" --remotes <remotes>
bash "$DEV_BOT_ROOT/src/agentic/git/tools/release.sh" release --version "<version>" --notes-file "<notes file>" --remotes <remotes>
```

Run them one at a time, in that order, and report each step's outcome.

- **`merge`** first folds every `fixup!`/`squash!`/`amend!` commit not yet on the default branch into
  its target — a branch with none is left untouched — then merges the branch you were on into the
  default branch and switches to it. On a conflict it aborts, restores your original branch, and exits
  `FATAL:` — stop there, nothing was tagged, and hand the conflicting paths to the user. If the local
  default branch had to be created and the merge then failed, it is left behind at the same commit as
  `origin/<default branch>` — harmless, and left deliberately.
- **`tag`** creates the annotated tag, its description being the notes file verbatim.
- **`push`** pushes the default branch and the tag to each remote. A failing remote does not stop the
  others; report which failed and the remediation the script printed. A pushed tag is never deleted.
- **`release`** publishes the GitHub release(s), titled with the version. If `gh` is missing, is not
  authenticated for the host, or a remote cannot host releases, it warns and continues — the tag push
  still stands. A genuine failure with an authenticated `gh` is an error, and its message says the tag
  is already pushed.

The checkout is left on the default branch; do not switch back.

## Notes

- `$DEV_BOT_ROOT` is exported by the harness. If it is unset, fall back to the script inside the
  dev-bot checkout.
- Close by reporting plainly: which branch was merged, the tag name, every remote the tag reached,
  and every release created.
