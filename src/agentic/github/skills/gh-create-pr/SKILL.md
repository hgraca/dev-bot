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
- `--reviewer @copilot` when Copilot should review.

Print the PR URL that `gh pr create` returns.

If the branch has no upstream, push it first — only after approval:

```bash
git push -u origin <branch>
```

## Copilot review

`--reviewer @copilot` requests GitHub Copilot code review. Copilot's **effort level** — Lite or
Balanced — is selected in the pull request's Reviewers panel on GitHub.com; the CLI cannot pin it
(`cli/cli#12921`). Lite is the default unless the organization or repository overrides it, so confirm
the level in the UI once the PR is open.

## Must not

- Do not open a pull request without showing the plan and getting explicit approval.
- Do not force-push.
- Do not compose the title or body from the branch name alone — read the commits and the diff.
