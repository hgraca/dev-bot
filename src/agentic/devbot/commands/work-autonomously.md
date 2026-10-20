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

3. **Iterate on Copilot review** — run this loop until a review introduces no new findings.

   - **Request** Copilot with the CLI's special reviewer value `@copilot` at creation, or
     `gh pr edit <pr> --add-reviewer @copilot`. A bare `copilot` is not a reviewer. If the CLI
     rejects it, request the bot directly: resolve
     `gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id` and the PR node id,
     then call the GraphQL `requestReviews` mutation with `botIds`. Re-request explicitly after
     each push — Copilot does not re-review on its own.
   - **Lite effort** — neither the CLI nor the API sets it. A request inherits the PR's previous
     effort, then your personal Copilot setting, then the repository and organization defaults,
     then the built-in default (Balanced). Select Lite before requesting and re-select it for every
     request. Copilot records the level in its review body (`**Review effort:**`); if it reports
     anything else, ask the user to set Lite and re-request before addressing the findings.
   - **Wait** — 5 minutes after each request before the first check. If the review has not landed,
     re-check every 5 minutes, for a maximum of 12 checks per request (the first check counts).
     Then stop and ask the user for instructions.
   - **Read** — fetch all pages (`gh api --paginate`). Select the new review by `submitted_at`,
     then its bot-authored comments by `pull_request_review_id` — `/comments` has `created_at`, not
     `submitted_at`. Read **both** the line comments (`.../pulls/<pr>/comments`) and the review
     body (`.../pulls/<pr>/reviews`); findings live in each.
   - **Checkout** — confirm the checkout is the PR's head branch before editing: an explicit
     `--head` may differ from the checked-out branch. Work in a clean checkout or worktree of that
     branch and push explicitly to it.
   - **Fix** — address every finding as per your own recommendation, commit each as a `fixup!`
     (`devbot:git-fixup-commits`), and push.
   - **Mark** — reply with what changed, then resolve the thread. A false positive gets a reply
     explaining why. A finding that exists only as a review-body row has no thread: record its
     resolution in a PR comment. This posting is the deliberate exception to
     `devbot:address-review`'s local-only rule.
   - **Track** — follow the underlying issue and affected code across both sources, keeping comment
     IDs for the replies and resolutions. A re-raised finding already addressed or judged a false
     positive does not restart the loop.

4. **Hand back** — stop and report the pull request. The reviewer will review it themselves, squash
   the fixups and merge.
