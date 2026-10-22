---
name: devbot:work-autonomously
description: Work a task autonomously to a review-clean PR — from a task given inline, a file path or a URL, resuming work already in progress.
---

Work the task below autonomously, end to end, without stopping for input until the final hand-back.

Task: $ARGUMENTS

## Steps

1. **Resolve the task** — the argument is the task itself. An existing file path is read, a URL is
   fetched, and anything else is taken as the task in the user's own words. With no argument at
   all, ask for the task before doing anything else.

2. **Assess progress** — the work may be half done, so derive the state before changing anything;
   never assume a fresh start. Collect the default branch
   (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`), the commits already on
   the current branch (`git log --oneline <default>..HEAD`), any open pull request
   (`gh pr list --head <current-branch> --state all --json number,url,state,mergedAt` — ask for
   **all** states and let the newest result decide; a query restricted to open pull requests cannot
   tell a merged or closed one from none at all), its latest Copilot review with the threads
   already addressed, and `git status --porcelain`. Report that state in three lines, then resume
   at the first incomplete step, without waiting for confirmation:

   - **No commits yet** — implement the task from scratch.
   - **Commits, and no pull request in any state** — finish the task, self-review, then open the
     pull request.
   - **Pull request open** — finish the task, self-review only the commits made since the last
     review, then resume the loop below where it stopped.
   - **Pull request merged or closed** — stop and ask whether to start a new branch.
   - **Uncommitted changes that are not this task's** — stop and ask; never stash or discard them.

   The current branch is the task's identity: continue it rather than cutting a new one from the
   default branch, never reopen a closed pull request, and never re-request Copilot while a review
   is still pending.

3. **Work the task** — implement what remains of it, committing in small atomic commits on the
   current branch as you go (`devbot:git-atomic-commits`).

4. **Self-review with @code-reviewer** — when the task is done, delegate to `@code-reviewer` a
   review of the changeset against the default branch — the whole of it, or on a resumed branch
   whose pull request is already open, the commits made since the last Copilot review — carrying
   the task's intent and acceptance criteria. Address every finding as per your own recommendation, amending your own
   commits (`devbot:git-fixup-commits`, respecting the rewrite-safety rule in `devbot:git-commits`)
   — then push the branch and open a pull request onto the default branch following the
   `devbot:gh-create-pr` skill, requesting `@copilot` as a reviewer. When the pull request already
   exists, push to it instead of opening another one.

5. **Iterate on Copilot review** — run this loop until a review introduces no new findings.

   - **Request** Copilot with the CLI's special reviewer value `@copilot` at creation, or
     `gh pr edit <pr> --add-reviewer @copilot`. A bare `copilot` is not a reviewer. If the CLI
     rejects it, request the bot directly: resolve
     `gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id` and the PR node id,
     then call the GraphQL `requestReviews` mutation with `botIds`. Re-request explicitly after
     each push — Copilot does not re-review on its own — but skip the request while a review is
     still pending, and do not ask for one you have already read.
   - **Lite effort** — neither the CLI nor the API sets it. A request inherits the PR's previous
     effort, then your personal Copilot setting, then the repository and organization defaults,
     then the built-in default (Balanced). Select Lite before requesting and re-select it for every
     request. Copilot records the level in its review body (`**Review effort:**`); if it reports
     anything else, ask the user to set Lite and re-request before addressing the findings.
   - **Wait** — 1 minute after each request before the first check. If the review has not landed,
     re-check every 1 minute, for a maximum of 60 checks per request (the first check counts).
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

6. **Hand back** — stop and report the pull request. The reviewer will review it themselves, squash
   the fixups and merge.
