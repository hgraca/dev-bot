---
date: 2026-09-20
keywords: ["no-vcs", "release-file", "gitignore", "ignore-md", "git-changelog"]
---

# The `*no-vcs*` rule lives in the user's global gitignore, not the repo's

`git check-ignore -v release.v1-5.no-vcs.md` resolves to
`/home/herberto/.gitignore:2:*no-vcs*` — the pattern is in the developer's
**global** `~/.gitignore`, not in this repo's `.gitignore` (which has no
`no-vcs` rule). So a grep of the repo for the rule that makes release files
uncommittable comes up empty, and a fresh machine without that global file
would happily commit them.

This compounds with `.agents/memory/active/ignore.md` ("NEVER read nor modify
any file or folder with `no-vcs` in the name, unless explicitly directed"), and
devbot's own release convention collides with it: `devbot:git-changelog` writes
`release.v<MAJOR>-<MINOR>.no-vcs.md` at the repo root, so the artifact the skill
produces is also an artifact agents are forbidden to open. Checking whether an
existing release file complies with the skill's rules (e.g. the 72-character
bullet cap) therefore requires explicit user direction first — scout read one
of these unasked during context gathering.

Handling: treat `release.*.no-vcs.md` as user-directed-only. Read or edit one
only when the user asks, and when the pipeline needs the decision made, ask
rather than assume the file's contents.

The pattern matches any path containing the token, filenames included, so even
a note about the rule cannot be named after it: this file was first written as
`20260920095031-no-vcs-ignore-rule-lives-in-global-gitignore.md` and
`git check-ignore` rejected it as uncommittable. Name such notes without the
token. The `ignore.md` prohibition is likewise filename-based, so a file can be
off-limits merely for what it is called.
