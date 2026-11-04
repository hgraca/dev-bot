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
- In a `supervisor: true` project, resolve the **owning project** of the changeset
  (`devbot tool project-for-path <file>`) and run every command below in it. `cd "$owner"` once
  covers git and `gh`; if you stay in the supervisor root, pass `git -C "$owner"` to every git
  call and `--repo <owner-slug>` to every `gh` call. The supervisor root has no remote, so a
  command run there resolves nothing. One PR, one repository.

## Determine the base

The base is the repository's default branch — never assume `main`:

```bash
gh repo view [<owner-slug>] --json defaultBranchRef --jq .defaultBranchRef.name
```

The head is the given branch, or the current one (`git [-C "$owner"] rev-parse --abbrev-ref HEAD`).

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
  [--repo <owner-slug>] \
  --base <default-branch> \
  --head <branch> \
  --title '<title>' \
  --body '<body>' \
  [--draft] \
  [--assignee @me]
```

- `--draft` when the PR is not ready for review.
- `--assignee @me` when the user should be the assignee.
- **No `--reviewer` here.** A rejected reviewer aborts creation, leaving no PR to repair; Copilot is
  requested after the PR exists (see [Copilot review](#copilot-review)).

Print the PR URL that `gh pr create` returns.

If the branch has no upstream, push it first — only after approval:

```bash
git [-C "$owner"] push -u origin <branch>
```

## Reference the PR by its URL

Reference every pull request by its URL — in a hand-back, a status report, a review summary, a
question, anywhere you name one. Give the full link, never a bare number, `#<number>`, or "the PR":
none of them identifies the repository, so the reader has to go looking.

`gh pr create` prints the URL; `gh pr view <url> --json url` recovers it afterwards. A pull request
that does not exist yet has no URL — name the branch instead.

## Copilot review

Requesting Copilot's review is the **default for every pull request**: skip it only when the user
explicitly asked to. Request it **after** the PR exists — never as a `gh pr create` flag, because a
rejected reviewer makes `gh` abort creation (`could not request reviewer: '@copilot' not found`) and
leaves no PR to repair:

```bash
gh pr edit <url> [--repo <owner-slug>] --add-reviewer @copilot
```

Confirm the request actually registered: `gh pr edit` can exit 0 without queuing it, and
`--json reviewRequests` does not list bot reviewers, so the signal is a `review_requested` event
whose reviewer is `Copilot` in the PR timeline. Page through it — the event can be past the first
page:

```bash
gh api --paginate repos/<owner>/<repo>/issues/<number>/timeline \
  --jq '.[] | select(.event=="review_requested" and .requested_reviewer.login=="Copilot") | .created_at' \
  | tail -1
```

If it did not register, retry with the GraphQL mutation. Resolve both ids first — a new PR has no
prior Copilot review to read the bot id from:

```bash
bot_id="$(gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
pr_id="$(gh pr view <url> --json id --jq .id)"
gh api graphql -f query='mutation($pr: ID!, $bot: ID!) { requestReviews(input: {pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }' \
  -f pr="$pr_id" -f bot="$bot_id"
```

A zero exit from the mutation is not proof the review was queued: re-read the timeline the same way
and require a `Copilot` `review_requested` event newer than the attempt. If none appears, report the
failure and carry on — a failed request never blocks the PR. Copilot's effort level is selected in
the PR's Reviewers panel, not the CLI — select Lite when the review should run at that level.
Iterating on the review is not this skill's job; the loop lives in `devbot:gh-review-loop`.

## Must not

- Do not open a pull request without showing the plan and getting explicit approval.
- Do not force-push — the guards module blocks it. The pre-merge squash is published by the human
  with `--force-with-lease` (see `devbot:git-fixup-commits`).
- Do not compose the title or body from the branch name alone — read the commits and the diff.
- Do not pass `--reviewer` to `gh pr create` — a rejected reviewer aborts creation.
- Do not skip the Copilot review request unless the user explicitly asked to.
