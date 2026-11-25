---
name: devbot:review-loop
description: "Use when a review→fix cycle must be driven to convergence, locally with @reviewer or through a pull-request reviewer. Triggers on 'run the review loop', 'address the review comments', 'iterate until the reviewer is happy'."
---

# Review Loop

The reviewer-agnostic review loop: request a review, read every finding, fix each as a fixup,
answer each one, and repeat until a round introduces no new findings. A clean round is not the
finish: gate the branch, squash the fixups into their targets, and stop one step before the merge.

Reviewers plug in through an adapter. Two are in use today:

| Adapter                   | Request                              | Await      | Read                           | Answer                                       |
| ------------------------- | ------------------------------------ | ---------- | ------------------------------ | -------------------------------------------- |
| **Local** — code reviewer | delegate a `task` with the changeset | its return | the findings list              | address them; nothing is posted              |
| **Remote** — pull request | the host's reviewer skill            | that skill | every place it writes findings | reply and resolve, as the adapter prescribes |

## When to Apply

- Reviewing a changeset before the pull request exists — the session's code reviewer, `@reviewer`
  interactively and `@code-reviewer` under `devbot:auto-dev`.
- Working a pull request's reviewer — Copilot, a human, another bot — to a clean state.
- A command drives it: `devbot:full-loop`, `devbot:gh-review-loop`, `devbot:auto-dev`.
- The user asks to run the review loop, address the review comments, or "iterate until it's happy".

## MUST

- **Fix every finding as a `fixup!`** (`devbot:git-fixup-commits`), one commit per finding.
- **Answer every finding** — a fix or a reasoned refusal, never silence. A false positive is
  answered in the same form as a fix.
- **Convergence is a round, not a thread list.** A round introduces no new findings only when
  every place the reviewer writes them is clear: an empty thread list with open issues still in
  the review body has not converged.
- **Gate before the history is touched.** The local adapter gates on the project's checks, the
  remote adapter on the required checks and the pull request's mergeability.
- **Squash the fixups into their targets** (`devbot:git-fixup-commits`). The branch that leaves
  this skill carries no `fixup!` commit.
- **Stop one step before the merge** — the merge is the user's.

## The loop

Run the steps in order until a round introduces no new findings.

### Request

Ask the adapter's reviewer for a round. Local: delegate to the session's code reviewer —
`@reviewer` interactively, `@code-reviewer` when `devbot:auto-dev` drives — with the commits under
review, the intent and the plan; the report it returns is the round. Remote: the reviewer skill's
request, verified as that skill requires — an exit code is not a registered request.

### Await

Local: the delegation returns, there is nothing to poll. Remote: the reviewer skill's wait — never
hand-roll a sleep loop for it.

### Read

Every place the reviewer writes findings, not only the threads. Local: the report's findings, each
with its file and the change it needs. Remote: the adapter's sources, the threads **and** the review
body. Keep each finding's identity so a re-raised one is recognised as already answered.

### Fix

Address every finding as per your own recommendation, one `fixup!` commit per finding, against the
commit that introduced the code. A finding you reject gets no commit — it gets an answer.

Remote: push the fixups before re-requesting. The reviewer sees only the pushed tip, so a re-request
on an unchanged head reviews nothing new.

### Answer

Local: resolve it in the code and record the decision; nothing is posted, `devbot:address-review`
is local-only. Remote: reply and resolve in the adapter's format, a false positive included.

### Re-enter

Repeat from [Request](#request). A finding already answered does not restart the loop; a new one
does. Stop when a round introduces no new findings, then gate.

### Gate

The branch still has to pass before the history is touched. Local: the project's own checks —
`make lint` and `make test`, or the project's documented equivalents. Remote: the adapter's gate,
the required checks green and the pull request mergeable — the adapter also re-checks it inside the
loop and sends a failing check back to [Request](#request).

## Finish

Squash the fixups into their targets (`devbot:git-fixup-commits`), showing the plan and getting
approval first. Then the branch's state decides the rest:

- **Pre-push** — the branch has never been pushed, so the squash is local history: nothing to
  force-push. Hand it back for the pull request (`devbot:gh-create-pr`).
- **Post-push** — an open pull request means the squash rewrites published history: hand the user
  the exact `git -C <owner> push --force-with-lease=<branch>:<expected-sha> origin
<new-head>:<branch>` command. `<owner>` is the owning project (`devbot tool project-for-path
<file>`), and `devbot:git-fixup-commits` owns the lease value. The guards module blocks the
  agent's force-push; the human publishes it. A squash rewrites commits without changing the tree,
  so the checks stay green.

Never merge. Never force-push.
