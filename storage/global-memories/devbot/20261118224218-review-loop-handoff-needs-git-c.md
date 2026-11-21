---
date: 2026-11-18
keywords: ["devbot", "gh-review-loop", "polyrepo", "force-with-lease", "git -C"]
trigger-on: ["gh-review-loop-handoff", "polyrepo-git-command"]
---

## The review loop's hand-off push must name the owning repo with `-C`

`devbot:gh-review-loop` finishes by handing the human a bare `git push --force-with-lease=<branch>:<sha> origin <sha>:<branch>`. In a polyrepo the human is often sitting at the polyrepo root, which has no `origin` at all, so the command dies with `fatal: 'origin' does not appear to be a git repository` before the guards are even relevant. Hand off `git -C <owner> push …` (owner resolved with `devbot tool project-for-path <file>`), or state the directory explicitly in the hand-off; the same applies to any copy-pasteable git command a skill emits for a polyrepo session. The lease value stays the one read from `git -C <owner> ls-remote origin refs/heads/<branch>`.
