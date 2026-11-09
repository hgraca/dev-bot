---
date: 2026-11-09
keywords: ["git", "annotated-tag", "cleanup", "release-notes"]
trigger-on: ["git-annotated-tag-message"]
---

## `git tag -m` silently strips `#` comment lines from the message

`git tag -a <tag> -m "<message>"` applies `--cleanup=strip` by default, which deletes
every line starting with `#` (comment lines) as well as leading/trailing blank lines. A
message that begins with a markdown heading — `# Release v1.2.0` — loses that heading
entirely, so `git tag -l --format='%(contents)' <tag>` returns only the body.

The trap is silent: the tag is created successfully and looks right in `git show`, which
renders the message minus the comments. It surfaces only when the consumer expects the
heading, e.g. a tool that recognises a release file by its `# Release v` first line.

Create the tag from a file instead, which is also how release tooling should do it:

```bash
git tag -a <tag> --cleanup=whitespace -F notes.md
```

`--cleanup=whitespace` trims surrounding whitespace but preserves `#` lines. When testing
code that reads tag messages, build fixtures with `-F --cleanup=whitespace` too — a fixture
using `-m` will hide exactly the bug the test is supposed to catch.
