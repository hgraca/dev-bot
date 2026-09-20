---
date: 2026-09-16
keywords: ['opencode', 'edit-tool', 'oldstring', 'fuzzy-match', 'verification']
trigger-on: ['opencode-edit-tool', 'edit-oldstring-fuzzy']
---

## The `edit` tool fuzzy-matches a near-miss `oldString` and still reports success

The `edit` tool's documentation says it fails with "oldString not found in content" when the string does not match, but in practice it tolerates small mismatches and applies a **fuzzy** match: an `oldString` that differed from the file — `?callable($constrainTrips = null)` where the file actually held `?callable $constrainTrips = null` — returned "Edit applied successfully". That failure mode is worse than an error, because the replacement can land on a span the caller never intended while the tool reports success. Never treat the success message as proof the edit landed where you meant: re-read the region (or `git diff`) after any edit whose `oldString` you assembled by hand rather than copying verbatim from a `Read` — and always re-read after an edit you were not confident about. Related trap: if an edit is followed by tooling that inspects the file (an LSP/linter diagnostic), those diagnostics may be a snapshot of the **pre-edit** content — an error referencing text you just replaced means "stale diagnostic", not "edit failed", so confirm against the file itself rather than re-editing or reverting.
