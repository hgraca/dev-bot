---
name: devbot:gh-create-pr
description: Open a pull request from a branch onto the default branch
---

Open a pull request for the branch below onto the repository's default branch, following the
`devbot:gh-create-pr` skill.

Branch: $1

If no branch is given, use the current branch.

## Steps

1. Resolve the branch: `$1` when provided, otherwise the current branch
   (`git rev-parse --abbrev-ref HEAD`).
2. Determine the default branch, then gather what the PR is about:
   `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, then
   `git log <default>..<branch>` and `git diff <default>...<branch>`.
3. **Local review gate — the question, not the run.** When no local review of this changeset has been
   made, include in this round the question whether to run it first (offer yes). In an automatic run
   (`devbot:auto-dev`) take yes without asking. Nothing is written here: the review runs in step 7,
   after the plan is approved, so it cannot mutate the branch before the user has seen what will be
   created.
4. Ask the user, in one round:
   - **Ticket ID** — the session's resolved Jira ticket when there is one (`devbot:jira-workflow`),
     otherwise ask. When the branch name carries one (e.g. `feature/ABC-123-foo` → `ABC-123`),
     offer it as the default. A ticket means the title must be prefixed with its key.
   - **Assignee** — set the user as the PR assignee?
   - **State** — ready for review, or draft?

   Do not ask about the Copilot review here: the PR opens without one, and that question comes after
   it exists (step 8). Use the harness's question tool when it has one; otherwise ask in plain text.

5. Compose the title and body per the `devbot:gh-create-pr` skill.
6. Show the user exactly what will happen — base branch, head branch, title, body, ready/draft,
   assignee, whether the branch will be pushed, and whether the local review will run first — and
   **wait for explicit approval**. In an automatic run (`devbot:auto-dev`) there is nobody to wait
   for: state the plan and continue.
7. On approval: run the local review when step 3 answered yes — the review pass
   `devbot:software-development` step 5 defines — addressing every finding as a fixup and squashing
   the fixups into their targets (`devbot:git-fixup-commits`). A review can change what ships: re-read
   `git diff <default>...<branch>` after the squash and refresh the body — and the title, when the
   scope moved — so the description matches the code that lands. Then push the branch if it has no
   upstream (`git push -u origin <branch>`), and create the PR **without a reviewer** — it opens
   unreviewed by Copilot by design:

   ```bash
   gh pr create --base <default> --head <branch> --title '<title>' --body '<body>' \
     [--draft] [--assignee @me]
   ```

8. Ask the user whether to run the Copilot review loop now (`devbot:gh-review-loop`). Only on a
   yes, request the review through the GraphQL mutation — it is the only path that registers a bot
   reviewer; `gh pr edit --add-reviewer @copilot` exits 0 while requesting nobody:

   ```bash
   bot_id="$(gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
   pr_id="$(gh pr view <url> --json id --jq .id)"
   gh api graphql -f query='mutation($pr: ID!, $bot: ID!) { requestReviews(input: {pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }' \
     -f pr="$pr_id" -f bot="$bot_id"
   ```

   Confirm it registered before looping — the mutation's exit code is not proof, so wait one second
   (`sleep 1`) and check the PR timeline for a `review_requested` event (see the skill's Copilot
   review section). On a yes, run `devbot:gh-review-loop` until a review introduces no new findings
   and the required checks are green. On a no, stop at the URL. In an automatic run
   (`devbot:auto-dev`) nobody is asked: request the review and run the loop by default.

9. Print the PR URL.

## Must not

- Do not create the PR before the user approves the plan.
- Do not create the PR while a local review has neither been made nor offered, or while fixups are
  still unsquashed.
- Do not force-push — it is blocked, and the pre-merge squash is published by the human
  (`devbot:git-fixup-commits`).
- Do not pass `--reviewer` to `gh pr create` — a rejected reviewer aborts creation.
- Do not use `gh pr edit --add-reviewer @copilot` — it registers nobody; use the GraphQL mutation.
- Do not request a Copilot review at creation: the PR opens without a reviewer, and the loop is
  requested only after the user asks for it — always, in an automatic run.
