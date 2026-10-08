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
