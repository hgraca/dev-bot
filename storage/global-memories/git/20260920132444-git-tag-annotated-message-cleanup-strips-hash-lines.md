---
date: 2026-09-20
keywords: ["git", "git-tag", "annotated-tag", "cleanup"]
trigger-on: ["git-annotated-tag", "git-tag-message-from-file"]
---

## `git tag -a -F <file>` silently strips lines starting with `#`

Creating an annotated tag from a file with `git tag -a <version> -F <file>` applies git's default message cleanup, which treats a leading `#` as a comment and removes the line — so a markdown release-note file loses its `# Release v1.5.0` heading, with nothing in the exit status or tag output reporting it (you only see it in `git cat-file tag <tag>`). Pass `--cleanup=whitespace` to keep comment-looking lines while still trimming surrounding whitespace (`--cleanup=verbatim` also works but keeps stray blank lines); verify by asserting on `git cat-file tag <tag>`, never on the tag merely existing.
