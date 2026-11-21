---
date: 2026-11-18
keywords: ["shell", "heredoc", "replay", "grep", "bats"]
---

# Replaying shell history needs heredoc-aware splitting, not line filtering

Rebuilding a repository from recorded commands (see the opencode session-db note) means executing
stored shell commands after dropping the ones that must not run (test suites, `docker`, `kill`,
the project's own lifecycle scripts). Three traps, each of which silently corrupts the replay:

- **Keep the heredoc terminator.** A splitter that finds `<<'TAG'` … `TAG` and emits only the body
  produces an unterminated heredoc: the rest of the command is swallowed as body text. Re-emit the
  newline + tag line as its own part.
- **Join the parts with nothing, not `\n`.** The text before a heredoc already ends with the opener's
  newline, so `'\n'.join(parts)` inserts a blank line at the top of every heredoc body. Appended
  blocks then gain a leading and trailing blank line — a diffstat that is 2–3 lines too long per
  append, easy to misread as a content bug.
- **Never match a command word with `\bword\b` against a whole line.** Filtering hazardous commands
  with `\bbats\b` also matches `cat > src/x_tests.bats <<'EOF'` and drops the file's opener, leaving
  the test body to execute as shell. Require the name at a command position:
  `(?<![-.\w])bats(\s|$)`.

Remap paths only in command text, never in a `cat > file` body (that is the file's content); do remap
a `python3 - <<'PY'` body, because it writes through absolute paths.
