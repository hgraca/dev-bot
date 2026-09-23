---
name: devbot:address-review
description: "Use when code review comments need resolving. Triggers on 'address the review', 'resolve the comments'."
---

# Skill: Address Review Comments

Address review comments by explaining each issue, assessing it, and proposing a resolution for user approval — all locally.

## When to Apply

- When review comments need to be addressed, regardless of source (GitHub PR, another agent, or a human reviewer)

## Input

A set of review comments to address, supplied by the caller (e.g. the `/devbot:gh-address-review` command).

## Procedure

### Step 1: Present every comment and collect all decisions — in one round

Present **all** comments together in a single message, then collect every decision in a single reply. Do not drip-feed comments one at a time, and do not wait for a decision between comments.

For each comment, include:

1. **Explain the issue** — restate what the reviewer is pointing out in plain terms.
2. **Give your assessment** — state whether you agree or disagree and why, referencing the code.
3. **Propose a resolution** — present the concrete option for how to resolve it (or an argument for no change), and state your recommended resolution.

Then ask the user to decide on **all** comments at once. Record each decision. This is discussion only — do not write code or commit during this step.

If the user requests a revised proposal for some comments, present a new round containing only those comments, following the same batched pattern, until every comment has a decision.

### Step 2: Implement and commit — only after every comment is decided

Once **all** comments have a decision, and not before:

1. **No code change needed** (per comment) — do not touch the code; the resolution is the explanation itself.
2. **Code change needed** (per comment) — make the change and commit it. One commit per comment addressed.
3. **Record each decision locally** — an issue is resolved only after the user decided it and the code (if any) is committed.

When a comment's fix corrects code that a commit unique to the current feature branch introduced, record it as an **atomic fixup commit** against that commit (`git commit --fixup=<sha>`), one fixup per comment. On a feature branch this is the required form, not a preference — the fixups are squashed into their targets before the branch is merged (see `devbot:git-fixup-commits`). Never record a fixup on the default branch; a correction there is a normal follow-up commit. Do not bundle multiple comments into one commit.

## MUST

- Address every unresolved comment — do not skip any.
- Present all comments together in a single round — explain, assess, and propose a resolution for each before collecting any decision.
- Collect the user's decisions for all comments in one reply — do not wait for a decision between comments.
- Defer all implementation until every comment has a decision — never write code or commit mid-discussion.
- Obtain an explicit decision from the user on each comment.
- Keep all actions local — never post replies, comments, or resolutions back to the review source.
- Record each comment fix as an atomic fixup commit against the branch commit that introduced the code — keep it atomic, squashable into its target, and traceable. On a feature branch this is required; squash before merging, and never record a fixup on the default branch.

## MUST NOT

- Post replies, comments, or resolutions back to the review source — all communication is local only.
- Write code, make commits, or mark issues resolved while any comment is still undecided.
- Discuss comments one at a time — present them all together in a single round.
- Skip the explain/assess/propose step for any comment.
- Ignore or dismiss review comments without explanation.
- Bundle multiple comment fixes into a single commit.
