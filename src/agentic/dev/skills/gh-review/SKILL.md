---
name: gh-review
description: "Addresses code review comments on a GitHub PR. Use this skill whenever a PR has external review comments that need resolving — by explaining reasoning or making code changes — or when the user says 'address the review', 'respond to this comment', or 'resolve this thread'."
---

# Skill: GitHub PR Review Resolution

Address all code review comments on GitHub PR by reading comments, making code changes, and explaining reasoning.

## When to Apply

- When GitHub PR has review comments that need to be addressed
- When invoked via `/gh-review` command with PR number

## Input

PR number (`$1`).

## Procedure

### Step 1: Read PR comments

Use `gh` CLI to read all review comments on PR `$1`. Prefer `--json` output and pipe through `cat` to avoid shell-piping truncation:

- `gh pr view $1 --json title,body,state,comments`
- `gh api repos/{owner}/{repo}/pulls/$1/comments` — line-anchored review comments (most relevant)
- `gh api repos/{owner}/{repo}/pulls/$1/reviews` — top-level review summaries

### Step 2: Ensure correct branch

Use `git` MCP to verify you are on branch associated with PR. Switch if needed.

### Step 3: Address each comment

For each review comment:

1. **If no code change needed** — reply to comment on PR explaining reasoning and resolve comment.
2. **If code change needed** — make change and commit. One commit per comment addressed. Use descriptive commit message referencing review comment. Reply to comment on PR explaining reasoning and resolve comment.

### Step 4: Improve reviewer

After all comments addressed, follow `improve-reviewer` skill to improve reviewer agent and/or its skills based on issues found by external reviewer in this session.

## MUST

- Address every unresolved comment — do not skip any.
- One commit per code-change comment — keep changes atomic and traceable.
- Explain reasoning clearly for all comments addressed.

## MUST NOT

- Ignore or dismiss review comments without explanation.
- Bundle multiple comment fixes into single commit.
