---
date: 2026-10-27
keywords: ["git", "github", "squash merge", "commit subject", "pull request title"]
trigger-on: ["pull-request-squash", "commit-ordering"]
---

## GitHub's squash-merge titles the commit from the branch's LAST commit

When a pull request is squash-merged and the title is not edited, GitHub uses the subject of the
branch's final commit as the squashed commit's message — not the PR title, not the first commit.
A branch ordered "fix → feature → staging wrapper" therefore lands on the default branch as
"ci: deploy to staging on dispatch", which describes a fraction of what the merge actually did and
misleads every later `git log` reader. Two habits prevent it: put the commit that names the whole
change last, or set the squash title explicitly at merge time (the PR title is usually the right
text). Worth flagging in a hand-back whenever the branch ends on an increment rather than the main
change.
