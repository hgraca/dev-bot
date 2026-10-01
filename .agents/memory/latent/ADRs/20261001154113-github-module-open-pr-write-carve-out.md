---
date: 2026-10-01
keywords: ["github", "open-pr", "gh-cli", "module-posture"]
---

## The github module gains one scoped write capability: open a PR

`src/agentic/github/` was deliberately read-only: `gh-make-review` and `gh-address-review` both
forbid any GitHub write, and the module's docs stated that nothing is written back to GitHub. The
`devbot:open-pr` skill and its `open-pr` command add the module's first write — `gh pr create`, plus
the `git push -u origin <branch>` a never-pushed branch needs — and the `docs.md` posture is amended
to name that single exception.

The carve-out is deliberately narrow. Only creating a pull request writes; every review-side
operation stays local, and no command replies to, resolves, or comments on a PR. Approval gates the
write: the command shows base, head, title, body, ready/draft state, assignee, reviewers and any
pending push, and waits for the user's explicit go-ahead before running anything.

Opening a pull request is a request to the repository, not communication with reviewers, which is why
it reads as a different class of operation from the read-only commands — and why it needed its own
record rather than a quiet edit to the module's stated posture.
