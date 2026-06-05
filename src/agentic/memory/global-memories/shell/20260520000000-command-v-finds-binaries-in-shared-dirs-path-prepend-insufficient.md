---
date: 2026-05-20
keywords: ["shell", "bash", "testing", "PATH", "command -v"]
---

## `command -v` finds binaries in shared system dirs — PATH prepend alone is insufficient for test isolation

When writing shell script tests that mock commands (docker, uv, etc.) by prepending a `mock-bin` directory to PATH, the real binary is still found if it lives in a shared essential directory like `/usr/bin` (which on modern Linux is the same as `/bin` via symlink). `command -v docker` returns 0 even when `mock-bin` is first in PATH, because the real docker is still reachable later in PATH. The fix: build a fully-isolated PATH using a curated symlink directory — symlink only the essential system tools (grep, mkdir, chmod, stat, env, bash, etc.) into an `isolated-bin` dir, then use `PATH="${MOCK_BIN}:${isolated_bin}"` with no other dirs. This ensures that commands not explicitly mocked are genuinely absent from PATH. Note: `command -v` also finds non-executable files (returns 0), so creating a non-executable stub does not make `command -v` fail.
