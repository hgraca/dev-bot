---
date: 2026-10-28
keywords: ["format-md", "bats", "prettier", "extension"]
---

# Never run a format-* tool on a file of another language

Each `format-*` tool pins its parser (`prettier --parser markdown|yaml|json`) and ignores the
argument's extension, so pointing one at a file of another language succeeds and rewrites it in that
parser's shape. Running `format-md` over `datasources_tests.bats` during a commit's format step
inserted a blank line after every shell line and re-indented the comment blocks — a 2 370-line diff
on a file that was meant to gain a 31-line test.

The commit protocol says to run every *applicable* `format-*` tool over the files a commit changes;
applicable is decided by extension, not by the tool being installed. Check `git diff --stat` after
the format step: a file whose diff dwarfs the change is the signal, and the recovery is
`git restore --source=<commit> -- <file>` before re-staging.
