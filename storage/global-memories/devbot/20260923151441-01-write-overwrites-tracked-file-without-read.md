---
date: 2026-09-23
keywords: ["devbot", "write", "tooling"]
trigger-on: ["devbot-write-tool"]
---

## The `write` tool overwrites a tracked file without a prior read, despite its documented guard

`write` documents that it "will fail if you did not read the file first" when the target already exists, but it does not enforce that: writing to an existing path overwrites it silently and returns success. Creating a new file whose name collides with an existing one — a new test beside a test with the same class name, for example — therefore destroys the existing content with no signal, and the loss only surfaces later in a confusing diff.

Check the target first whenever the path was not created in this session: `git ls-files <path>` or a directory listing. Recovery is `git show HEAD:<path>` when the file was committed, and nothing when it was not — which is why the check, not the recovery, is the point.
