---
date: 2026-05-20
keywords: ["shell", "bash", "test-fixture", "awk", "PATH isolation"]
---

## Test fixture isolated PATH excludes tail/head — use awk NR instead

When shell integration tests use a mock-bin + isolated-bin pattern (symlinks to a fixed set of tools prepended to PATH), `tail` and `head` are typically not included in the symlinked set. Scripts that call `tail -n +2` or `head -1` will exit 127 inside the test harness. Replace these with `awk 'NR>1'` (skip header) and `awk 'NR==1'` (print header) respectively — `awk` is always in the fixture set. Check the fixture's symlink loop to know exactly which tools are available before writing the implementation.
