---
date: 2026-11-18
keywords: ["opencode", "session-db", "recovery", "git", "transcripts"]
---

# Rebuild a destroyed repository from opencode's session database

When a working copy loses `.git` (disk failure, a bad wipe) with unpushed commits, the opencode
database is a complete-enough record to rebuild them. `opencode.db` keeps `session_message` rows for
every assistant turn, and a tool part's `state.input` holds the exact payload: `edit` carries
`path`/`oldString`/`newString`, `write` carries the whole file, `shell` carries the command that
wrote a file (heredoc, `sed -i`, `python3 - <<`), and every `git commit` invocation is there with its
message. `session_v2` maps session → directory, so worktree sessions are found too.

Replay them in global chronological order against a clean checkout of the last pushed commit:

- apply `edit`/`write` payloads directly, and run mutating shell commands with the original repo path
  remapped to the replay checkout;
- skip a tool call whose recorded `state.status` is `error` **only for `edit`/`write`** (atomic
  no-ops); a failed shell command often wrote its file first and then failed a test, so replay it —
  unless a later successful near-identical command supersedes it (a retried heredoc would duplicate);
- run the project's formatter after each `edit`/`write` of a formatted file: an edit's `oldString`
  is written against the *formatted* file the on-edit hook produced, not the raw text;
- at each recorded commit, stage its recorded `git add` paths and commit with the recorded message,
  author and timestamp.

Verification is what makes this trustworthy: the transcript records each commit's diffstat
(`N files changed, X insertions, Y deletions`), so a faithful replay reproduces it. In the dev-bot
recovery this reproduced 24 of 31 commits exactly and the rest within 1–2 lines, and every file the
backup still held came out byte-identical.
