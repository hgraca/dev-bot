---
date: 2026-11-20
keywords: ["shell", "bats", "refactor", "helper-extraction", "code-review"]
aliases: ["split test file", "line-range extraction drops comments", "helper extraction loses rationale"]
trigger-on: ["bats-file-split", "test-helper-extraction"]
---

## Splitting a bats file by line ranges silently drops the comment above each function

A mechanical split — slice the file into themes, move `setup()` and the fixtures into a `*_test_helper.bash` — is safest done by line ranges, and ranges that start at the `function_name() {` line leave behind the comment block above it. The tests keep passing, and the damage is invisible to a green suite: `# Args:` lines, the rationale for a fixture's derivation, and the security property a suite protects all vanish from the file five other files now depend on. Two things catch it. Start each range at the first line of the comment block, not at the function, and carry the original file header into every theme file (with a "split from …" line) rather than replacing it with a generated one-liner. Then verify the result by parsing both revisions rather than reading them: extract every `@test` body from the old file and from the new ones, assert the count matches and each body is byte-identical, and do the same for the helper functions against the old `setup()`. A reviewer will otherwise find the loss one comment at a time.
