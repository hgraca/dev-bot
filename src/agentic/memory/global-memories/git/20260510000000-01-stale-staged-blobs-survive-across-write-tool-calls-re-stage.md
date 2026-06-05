---
date: 2026-05-10
keywords: ["git", "commit", "blob", "hook"]
---

## Stale staged blobs survive across `write` tool calls — re-stage before commit

When the `write` tool creates/overwrites a file that was _already staged_ with different content, the staged index entry points to the OLD blob OID. The new file content is on disk but the index still references a blob that may have been GC'd or never existed in the object store under that OID. Symptom: `git commit` aborts with `error: invalid object 100644 <oid> for '<path>' / error: Error building trees`, repeatedly, even after the file looks correct on disk. The earlier `git add` (or auto-staging by another tool) captured a now-stale OID.
Fix: When this happens, `git reset HEAD <file>` to drop the stale entry, then `git add <file>` to re-stage from current disk contents, then commit. Defensive habit: when an earlier `git status` shows files as staged but you've since rewritten them with `write` or `edit`, always re-`git add` before commit. Reproduced twice in one session (2026-05-10) while creating the git-hook-run-tests module — `docs/tools/index.md` and `docs/tools/run-tests.md` both hit it. See [[patterns]] for git commit workflow.
