---
name: devbot:gh-create-pr
description: "Use when opening a pull request from a branch. Triggers on 'open a PR', 'create a pull request', 'raise a PR'."
---

# Open PR

Open a pull request from a branch onto the repository's default branch with the GitHub CLI (`gh`). The
PR description follows the same rules as a commit message — see `devbot:git-commits`.

## When to Apply

- The `gh-create-pr` command asks for a pull request to be opened.
- The user asks to open, create, or raise a pull request from a branch.

## Preconditions

- `gh` is installed and authenticated (`gh auth status`). If it is not, stop and say so — do not
  guess at credentials.
- The head branch exists and holds the commits the PR is for.

## Determine the base

The base is the repository's default branch — never assume `main`:

```bash
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

The head is the given branch, or the current one (`git rev-parse --abbrev-ref HEAD`).

## Title

Same rules as a commit subject (`devbot:git-commits`): imperative mood, lowercase start, no trailing
period, at most 72 characters.

When a ticket ID applies, prefix it:

```text
MY-TKT: add the gh-create-pr command
```

Without a ticket, use the bare imperative subject.

## Body — the why, not the how

The PR body carries the same two lists a commit body does — what the branch addresses and what it does
about it. The diff already shows the how.

```text
Problems:
- <what was wrong, missing, or at risk — ≤72 chars>
- <what was wrong, missing, or at risk — ≤72 chars>

Solutions:
- <what this change does about it — ≤72 chars>
- <what this change does about it — ≤72 chars>
```

One bullet per distinct problem and solution, each ≤72 characters. Base them on the branch's commits
and its diff against the default branch, not on the branch name alone.

## Open the PR

**Show the user the full plan and wait for explicit approval before writing anything.** The `gh-create-pr`
command drives this, but the rule holds whenever this skill is used. Then:

```bash
gh pr create \
  --base <default-branch> \
  --head <branch> \
  --title '<title>' \
  --body '<body>' \
  [--draft] \
  [--assignee @me] \
  [--reviewer @copilot]
```

- `--draft` when the PR is not ready for review.
- `--assignee @me` when the user should be the assignee.
- `--reviewer @copilot` when Copilot should review — the CLI's special reviewer value, not a login.
  Set your personal Copilot effort to Lite first, or create without it and request the review in the
  PR's Reviewers panel after selecting Lite.

Print the PR URL that `gh pr create` returns.

If the branch has no upstream, push it first — only after approval:

```bash
git push -u origin <branch>
```

## Copilot review

Request GitHub Copilot code review with the CLI's special reviewer value `@copilot` — at creation or
on an existing PR:

```bash
gh pr edit <pr> --add-reviewer @copilot
```

`@copilot` is not a normal login: the CLI maps it to `copilot-pull-request-reviewer[bot]`. A bare
`copilot` is not a reviewer and must not be used. Confirm the installed `gh` lists `@copilot` in
`gh pr edit --help` — older builds treat it as a login — and note it is not supported on GitHub
Enterprise Server. In a PR comment, `@copilot` simply mentions the bot.

If `gh` rejects the reviewer as not found, or no review arrives, request the bot directly — resolve
its node id and the PR node id, then call the GraphQL `requestReviews` mutation:

```bash
gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id
gh api repos/{owner}/{repo}/pulls/<pr> --jq .node_id
gh api graphql -f query='mutation($pr:ID!,$bot:ID!){requestReviews(
  input:{pullRequestId:$pr,botIds:[$bot]}){pullRequest{id}}}' -f pr=<pr-node> -f bot=<bot-node>
```

Re-request explicitly after each push — Copilot does not re-review on its own.

Copilot must run at **Lite** effort. Neither the CLI nor the API can set the effort: a request
inherits the effort already used on the PR, then the requestor's personal Copilot code-review
setting, then the repository and organization defaults, and finally GitHub's built-in default
(Balanced). Before requesting, make sure Lite is in effect — set your personal Copilot code-review
effort to Lite, or have the user select Lite in the PR's Reviewers panel. The choice does not
persist across requests. Copilot records the level it used in its review body
(`**Review effort:**`); if it reports anything other than Lite, ask the user to set Lite and
re-request before addressing the findings.

### Review loop

1. Wait 5 minutes after each review request before the first check.
2. Check for a Copilot review submitted after the latest request: fetch **all** pages
   (`gh api --paginate`), select the new review by `submitted_at`, then select its bot-authored
   comments by `pull_request_review_id` — `/comments` has `created_at`, not `submitted_at`.
3. If it has not landed, re-check every 5 minutes, for a maximum of 12 checks per request (the
   first check counts). After that, stop and ask the user for instructions.
4. Read **both** the line comments
   (`gh api --paginate repos/{owner}/{repo}/pulls/<pr>/comments`) and the review-body table
   (`gh api --paginate repos/{owner}/{repo}/pulls/<pr>/reviews`) — Copilot findings live in each,
   and older rounds can push them past the first page.
5. Confirm the checkout is the PR's head branch before editing — `gh-create-pr` accepts an explicit
   `--head` that may differ from the checked-out branch. Work in a clean checkout or worktree of
   that branch and push explicitly to it.
6. Address every finding and push the fixes.
7. **Mark each addressed comment** — reply with what changed, then resolve the thread. A finding
   judged a false positive gets a reply explaining why instead. For a finding that exists only as a
   review-body row there is no thread: record its resolution in a PR comment. This posting is the
   deliberate exception to `devbot:address-review`'s local-only rule, which governs the local review
   flow; the Copilot loop reports back to GitHub.
8. Track the underlying issue and affected code across both sources, keeping comment IDs for the
   replies and resolutions. A re-raised finding already addressed or judged a false positive does
   not restart the loop.
9. Request another review and repeat until a review introduces no new findings, in its comments or
   its body table.

Applying the findings is a write like any other: state the edit/commit/push/reply actions in the PR
plan and fix autonomously only when the user approved that. Otherwise present the findings for a
decision before editing (see `devbot:address-review`).

## Must not

- Do not open a pull request without showing the plan and getting explicit approval.
- Do not force-push.
- Do not compose the title or body from the branch name alone — read the commits and the diff.
