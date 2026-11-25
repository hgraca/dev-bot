---
name: devbot:full-review-loop
description: Run the full review path — local review, pull request, host review, squash — and hand the force-push and merge to the user
---

Run the complete review path for the current branch, from the local review to the merge handover.

Host: GitHub with GitHub Copilot as the remote reviewer — the shipped adapters (`devbot:gh-create-pr`
and `devbot:gh-review-loop`). On another host (GitLab, Bitbucket, …) the same steps apply with that
host's equivalents: the loop is `devbot:review-loop`'s, the mechanics are the host's. Never invent
another host's mechanics — ask.

## Steps

1. **Local loop** — run `devbot:review-loop` with `@reviewer` as the reviewer: delegate the
   changeset against the default branch, with the intent and the plan. Drive its loop and Gate until
   a round introduces no new findings, then stop before its Finish — this command owns both squashes
   and the handover. This and step 5 are two runs of the same loop, not two different loops.
2. **Gate** — run the project's checks (`make lint` and `make test`, or the project's documented
   equivalents); they must be green before the squash.
3. **Squash** — squash the local fixups into their targets (`devbot:git-fixup-commits`), showing
   the plan and getting approval. The branch that gets pushed carries no `fixup!` commit.
4. **Pull request** — open it with `devbot:gh-create-pr`, or the host's equivalent. Invoking this
   command answers that skill's two questions — step 1 was the local review, step 5 is the remote
   loop — but not its inputs: still show the plan (title, body, base, assignee) before creating, and
   never skip a required field.
5. **Remote loop** — run `devbot:review-loop` with the host's reviewer adapter; on GitHub that is
   `devbot:gh-review-loop` (Copilot). Drive its loop and Gate until a round introduces no new
   findings and every required check is green with the pull request mergeable, then stop before its
   Finish: steps 6 and 7 are this command's.
6. **Squash again** — squash the remote loop's fixups into their targets, showing the plan and
   getting approval first.
7. **Hand back** — give the user the exact `git -C <owner>
push --force-with-lease=<branch>:<expected-sha> origin <new-head>:<branch>` command, `<owner>`
   being the owning project (`devbot tool project-for-path <file>`). The user force-pushes and
   merges; the squash keeps the checks green because it rewrites commits without changing the tree.

When an **open** pull request already exists for the branch **and** the local loop and its squash are
done, start at step 5. A merged or closed pull request is not resumed — assess the branch first, as
`devbot:software-development` step 2 directs.

## Must not

- Do not merge, and do not force-push: the guards module blocks the push, and the merge is the
  user's.
- Do not skip the local loop — the remote reviewer is the second reader, not the first.
- Do not push the local loop's `fixup!` commits: the first push carries none. The remote loop does
  push its fixups — that is how the reviewer sees them — and step 6 squashes them.
- Do not let `devbot:review-loop` finish a round: stop it before its Finish, so nothing is squashed
  or handed over twice.
