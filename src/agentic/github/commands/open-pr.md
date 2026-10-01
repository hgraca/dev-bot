---
name: devbot:open-pr
description: Open a pull request from a branch onto the default branch
---

Open a pull request for the branch below onto the repository's default branch, following the
`devbot:open-pr` skill.

Branch: $1

If no branch is given, use the current branch.

## Steps

1. Resolve the branch: `$1` when provided, otherwise the current branch
   (`git rev-parse --abbrev-ref HEAD`).
2. Determine the default branch, then gather what the PR is about:
   `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, then
   `git log <default>..<branch>` and `git diff <default>...<branch>`.
3. Ask the user, in one round:
   - **Ticket ID** — if any. When the branch name carries one (e.g. `feature/ABC-123-foo` →
     `ABC-123`), offer it as the default.
   - **Assignee** — set the user as the PR assignee?
   - **State** — ready for review, or draft?
   - **Copilot reviewer** — request GitHub Copilot as a reviewer?

   Use the harness's question tool when it has one; otherwise ask in plain text.

4. Compose the title and body per the `devbot:open-pr` skill.
5. Show the user exactly what will happen — base branch, head branch, title, body, ready/draft,
   assignee, reviewers, and whether the branch will be pushed — and **wait for explicit approval**.
6. On approval: push the branch if it has no upstream (`git push -u origin <branch>`), then create
   the PR:

   ```bash
   gh pr create --base <default> --head <branch> --title '<title>' --body '<body>' \
     [--draft] [--assignee @me] [--reviewer @copilot]
   ```

7. Print the PR URL.

## Must not

- Do not create the PR before the user approves the plan.
- Do not force-push.
