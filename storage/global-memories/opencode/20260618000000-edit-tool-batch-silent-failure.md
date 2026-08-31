---
date: 2026-06-18
keywords: ["opencode", "edit-tool", "batch-edit", "silent-failure", "gotcha"]
---

## Edit tool batch edits silently fail across multiple files

When issuing 6 parallel `edit` calls in a single message (one per file), all returned "Edit applied successfully" but zero changes persisted to disk. Subsequent `read` and `bash tail/md5sum` showed files unchanged. Retrying the same 6 edits in a second parallel batch succeeded. Root cause unknown — possible race condition or caching layer. Workaround: after every batch edit, verify at least one file with `bash md5sum` or `grep` before trusting the success message. Never trust batch edit success without verification.
