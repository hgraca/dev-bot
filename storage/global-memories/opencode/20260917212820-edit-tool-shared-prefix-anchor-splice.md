---
date: 2026-09-17
keywords: ["opencode", "edit", "fuzzy-match", "anchoring"]
trigger-on: ["opencode-edit-tool", "file-edit-anchoring"]
---

## A long `oldString` whose opening lines recur elsewhere can be spliced into the wrong region

opencode's edit tool matches the supplied `oldString` with several fuzzy replacers, so an `oldString` whose opening lines also occur elsewhere in the file can be applied to a different region than intended. Observed on a 346-line test file: an edit whose `oldString` opened with a `run … / assert_success` block repeated across several tests and closed with `assert_equal … / }` reported `Edit applied successfully` while actually replacing an _unrelated_ test's body — silently destroying a passing test that the same commit would have shipped.

The failure is invisible to a content grep: searching for the text you inserted finds it, and if the pattern you grep for also exists pre-existing elsewhere in the file the check passes for the wrong reason. That is exactly how it slipped through once here — the verification grepped for a marker line that a different, untouched helper also contained.

Defensive practice: anchor an `oldString` on a line that is unique in the file (a distinctive comment, a test name, a specific identifier) rather than on a common boilerplate prologue; when rewriting a file programmatically, assert the match count is exactly 1 before writing; and verify an edit by reading the full diff, never by grepping for the inserted text.
