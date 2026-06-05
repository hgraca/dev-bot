---
date: 2026-05-20
keywords: ["shell", "docker", "mock", "test", "grep"]
---

## Mock `docker ps` ignores `--format` flag — use plain grep on full output

When mocking `docker` in shell tests, the mock script typically ignores flags like `--format '{{.Names}}'` and outputs a full table. Scripts that call `docker ps --format '{{.Names}}' | grep "^container-name$"` will fail because the mock returns a multi-column table row. Use `docker ps 2>/dev/null | grep "container-name"` instead — it works with both real Docker (table contains the name) and mocks that output full table rows.
