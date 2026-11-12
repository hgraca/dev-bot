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
3. Ask the user, in one round:
   - **Ticket ID** — the session's resolved Jira ticket when there is one (`devbot:jira-workflow`),
     otherwise ask. When the branch name carries one (e.g. `feature/ABC-123-foo` → `ABC-123`),
     offer it as the default. A ticket means the title must be prefixed with its key.
   - **Assignee** — set the user as the PR assignee?
   - **State** — ready for review, or draft?

   Copilot review is requested by default after the PR exists (step 6) — do not ask about it. Skip
   that request only when the user explicitly asked to.

   Use the harness's question tool when it has one; otherwise ask in plain text.

4. Compose the title and body per the `devbot:gh-create-pr` skill.
5. Show the user exactly what will happen — base branch, head branch, title, body, ready/draft,
   assignee, reviewers, and whether the branch will be pushed — and **wait for explicit approval**.
6. On approval: push the branch if it has no upstream (`git push -u origin <branch>`), then create
   the PR **without** a reviewer — a rejected reviewer aborts creation:

   ```bash
   gh pr create --base <default> --head <branch> --title '<title>' --body '<body>' \
     [--draft] [--assignee @me]
   ```

   Then request Copilot through the GraphQL mutation, unless the user explicitly asked to skip it.
   It is the only path that registers a bot reviewer — `gh pr edit --add-reviewer @copilot` exits 0
   while requesting nobody:

   ```bash
   bot_id="$(gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
   pr_id="$(gh pr view <url> --json id --jq .id)"
   gh api graphql -f query='mutation($pr: ID!, $bot: ID!) { requestReviews(input: {pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }' \
     -f pr="$pr_id" -f bot="$bot_id"
   ```

7. Print the PR URL. When Copilot was requested, confirm it registered — the mutation's exit code is
   not proof, so wait one second (`sleep 1`) and then check for a `review_requested` event in the PR
   timeline (see the skill's Copilot review section). A failed request does not invalidate the PR.

## Must not

- Do not create the PR before the user approves the plan.
- Do not force-push — it is blocked, and the pre-merge squash is published by the human
  (`devbot:git-fixup-commits`).
- Do not pass `--reviewer` to `gh pr create` — a rejected reviewer aborts creation.
- Do not use `gh pr edit --add-reviewer @copilot` — it registers nobody; use the GraphQL mutation.
- Do not omit the Copilot reviewer request unless the user explicitly asked to skip it.
