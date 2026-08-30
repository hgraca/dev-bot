---
name: devbot:address-review
description: "Addresses code review comments by discussing each one individually and deciding it, then implementing all approved changes only after every comment is decided — all locally. Use this skill whenever review comments (from GitHub, another agent, or a human) need resolving."
---

# Skill: Address Review Comments

Address review comments by explaining each issue, assessing it, and proposing solutions for user approval — all locally.

## When to Apply

- When review comments need to be addressed, regardless of source (GitHub PR, another agent, or a human reviewer)

## Input

A set of review comments to address, supplied by the caller (e.g. the `/devbot:gh-review` command).

## Procedure

### Step 1: Discuss each comment — one at a time

For each review comment, processed **one at a time**, in order:

1. **Explain the issue** — restate what the reviewer is pointing out in plain terms.
2. **Give your assessment** — state whether you agree or disagree and why, referencing the code.
3. **Propose a solution** — present the concrete option for how to resolve it (or an argument for no change). This is a proposal only.
4. **Get the user's decision on this comment** — the user approves it, or requests a revised proposal. If revised, re-discuss until decided.

Record the decision. Move to the next comment only after the current one is decided. This is discussion only — do not write code or commit during this step.

### Step 2: Implement and commit — only after every comment is decided

Once **all** comments have a decision, and not before:

1. **No code change needed** (per comment) — do not touch the code; the resolution is the explanation itself.
2. **Code change needed** (per comment) — make the change and commit. One commit per comment addressed. Use a descriptive commit message referencing the review comment.
3. **Record each decision locally** — an issue is resolved only after the user decided it and the code (if any) is committed.

When committing fixes to the changeset, use atomic fixup commits

## MUST

- Address every unresolved comment — do not skip any.
- Discuss comments one at a time — explain, assess, propose, and decide each comment before moving to the next.
- Defer all implementation until every comment has a decision — never write code or commit mid-discussion.
- Obtain an explicit decision from the user on each comment.
- Keep all actions local — never post replies, comments, or resolutions back to the review source.
- Make atomic fixup commits — keep changes atomic, squashable to the original commit, and traceable.

## MUST NOT

- Post replies, comments, or resolutions back to the review source — all communication is local only.
- Write code, make commits, or mark issues resolved while any comment is still undecided.
- Skip the explain/assess/propose step for any comment.
- Ignore or dismiss review comments without explanation.
- Bundle multiple comment fixes into a single commit.
