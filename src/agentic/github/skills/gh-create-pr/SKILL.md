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
- In a polyrepo project, resolve the **owning project** of the changeset
  (`devbot tool project-for-path <file>`) and run every command below in it. `cd "$owner"` once
  covers git and `gh`; if you stay in the polyrepo root, pass `git -C "$owner"` to every git
  call and `--repo <owner-slug>` to every `gh` call. The polyrepo root has no remote, so a
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

When the session has a Jira ticket, the title **must** start with its key — Jira links the pull
request to the issue from the key alone, so the prefix is not cosmetic:

```text
PROJ-1234: add the gh-create-pr command
```

Take the key from the ticket the session resolved (`devbot:jira-workflow`). Only when no ticket
exists, use the bare imperative subject.

**Exception — a pull request that implements none of the session's work.** Wrap-up can open a pull
request in another repository from what the session learned — `devbot:improve-reviewing` does exactly
that against the toolkit repository. The session's ticket tracks work in its own repository, so the
key would link this pull request to an issue it does not implement: use the bare imperative subject,
and that repository's own ticket key only when the improvement has one.

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

For the pull request in the [title exception](#title) — one that implements none of the session's
work — the two lists give way to one short section per change it makes: what the external evidence
showed, why the current instructions miss it, and the file that now covers it.

## Local review first

A pull request is the wrong place to discover the branch was never reviewed. When no local review
has been made of this changeset, ask the user whether to run it first, and run it on a yes: the
review pass `devbot:software-development` step 5 defines — the changeset is reviewed, every finding
addressed as a fixup (`devbot:address-review`), and the fixups squashed into their targets
(`devbot:git-fixup-commits`). The question is asked while the pull request is being planned, but the
review itself runs only after that plan is approved: it rewrites your commits, and a gate an
unapproved rewrite preceded is not a gate. A no is answered honestly: say that the branch will be
published unreviewed.

A local review can change what ships. Once its fixups are squashed, re-read the diff and refresh the
body — and the title, when the scope moved — before creating the pull request; a description written
against the pre-review diff describes code that no longer exists.

In an automatic run (`devbot:auto-dev`) there is nobody to ask: every loop runs by default, so run
the local review loop and squash, then open the pull request without that gate.

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

The pull request is opened **without a reviewer**. Once it exists, ask the user whether to run the
Copilot review loop (`devbot:gh-review-loop`) — request the review only on a yes, then run that loop.
In an automatic run (`devbot:auto-dev`) there is nobody to ask: request it and run the loop by
default.

Request it **after** the PR exists — never as a `gh pr create` flag, because a rejected reviewer
makes `gh` abort creation (`could not request reviewer: '@copilot' not found`) and leaves no PR to
repair.

**Use the GraphQL mutation. That is the only way.** `gh pr edit --add-reviewer @copilot` reports
success while requesting nobody — it never registers a bot reviewer — so it is not an option and
must not appear in a command:

```bash
bot_id="$(gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
pr_id="$(gh pr view <url> --json id --jq .id)"
gh api graphql -f query='mutation($pr: ID!, $bot: ID!) { requestReviews(input: {pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }' \
  -f pr="$pr_id" -f bot="$bot_id"
```

Resolve both ids on every request — a new PR has no prior Copilot review to read the bot id from.

Then verify, after a **one-second** gap: the mutation's exit code is not proof the review was
queued. Give GitHub a moment to surface the event, then look for a `Copilot` `review_requested`
event in the PR timeline. Page through it — the event can be past the first page:

```bash
sleep 1
gh api --paginate repos/<owner>/<repo>/issues/<number>/timeline \
  --jq '.[] | select(.event=="review_requested" and .requested_reviewer.login=="Copilot") | .created_at' \
  | tail -1
```

`--json reviewRequests` does not list bot reviewers, so it can never confirm this. If no `Copilot`
event appears, report the failure and carry on — a failed request never blocks the PR. Copilot's
effort level is selected in the PR's Reviewers panel, not the CLI — select Lite when the review
should run at that level. Iterating on the review is not this skill's job; the loop lives in
`devbot:gh-review-loop`.

## Must not

- Do not open a pull request without showing the plan and getting explicit approval.
- Do not force-push — the guards module blocks it. The pre-merge squash is published by the human
  with `--force-with-lease` (see `devbot:git-fixup-commits`).
- Do not compose the title or body from the branch name alone — read the commits and the diff.
- Do not pass `--reviewer` to `gh pr create` — a rejected reviewer aborts creation.
- Do not use `gh pr edit --add-reviewer @copilot` — it registers nobody; use the GraphQL mutation.
- Do not open a pull request while a local review of the changeset has neither been made nor
  offered, or while fixups are still unsquashed.
- Do not request a Copilot review at creation: the pull request opens without a reviewer, and the
  loop is requested only after the user asks for it — always, in an automatic run.
