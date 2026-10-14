---
name: devbot:work-autonomously
description: Work a task autonomously to a review-clean PR — implement it, self-review with @code-reviewer, then iterate on Copilot review until it finds nothing.
---

Work the task below autonomously, end to end, without stopping for input until the final hand-back.

Task: $1

If no task path or URL is given, ask for it before doing anything else.

## Steps

1. **Work the task** — read it from the given path or URL and implement it fully, committing in
   small atomic commits on the current branch as you go (`devbot:git-atomic-commits`).

2. **Self-review with @code-reviewer** — when the task is done, delegate to `@code-reviewer` a
   review of the whole changeset against the default branch, carrying the task's intent and
   acceptance criteria. Address every finding as per your own recommendation, amending your own
   commits (`devbot:git-fixup-commits`, respecting the rewrite-safety rule in `devbot:git-commits`)
   — then push the branch and open a pull request onto the default branch following the
   `devbot:gh-create-pr` skill, requesting `@copilot` as a reviewer.

3. **Iterate on Copilot review** — if Copilot was not requested at creation, request it
   (`gh pr edit <pr> --add-reviewer @copilot`). Wait for the review to land by polling the PR. Read
   **both** the line comments (`gh api repos/{owner}/{repo}/pulls/<pr>/comments`) **and** the
   review-body table (`gh api repos/{owner}/{repo}/pulls/<pr>/reviews`) — Copilot findings live in
   each. Fix every finding autonomously as per your own recommendation, commit each as a `fixup!`
   (`devbot:git-fixup-commits`), push, and request another Copilot review. Keep repeating this loop
   until Copilot raises no further findings.

4. **Hand back** — stop and report the pull request. The reviewer will review it themselves, squash
   the fixups and merge.
