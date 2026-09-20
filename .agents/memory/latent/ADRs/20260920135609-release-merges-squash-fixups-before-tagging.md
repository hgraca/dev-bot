---
date: 2026-09-20
keywords: ["release", "git", "fixup", "autosquash"]
see: ["ADRs/20260920132448-gated-release-command-script-owns-determinism.md"]
---

## `devbot:release` merge folds fixup commits before tagging

`merge` now folds every `fixup!`/`squash!`/`amend!` commit not yet on the default branch into its target — a non-interactive `git rebase --autosquash` (`GIT_SEQUENCE_EDITOR=:`) over the `origin/<default>..<source>` range — before it merges the source branch. A branch carrying no such commits is not rebased at all, so a fixup-free branch keeps its commit ids and the existing fast-forward path is untouched. `plan` prints the fixup count it will squash, keeping the preview and the executed steps from drifting (the core rule of the gated-release ADR). The trigger was a release branch carrying three `fixup!` commits: without this, the release tag would have frozen each correction as a standalone commit. On a rebase failure the rebase is aborted and the branch restored, matching `merge`'s existing all-or-nothing contract.
