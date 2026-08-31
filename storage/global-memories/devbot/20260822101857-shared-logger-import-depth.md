---
date: 2026-08-22
keywords: ["devbot", "logger", "import", "hooks"]
trigger-on: ["shared-logger-import"]
---

## Shared logger import depth (harness hooks)

The shared `_shared/logger.ts` is imported with a relative path whose depth depends on the file's directory nesting. Harness hooks under `src/harnesses/<harness>/hooks/` use `../../../_shared/logger.ts` (three levels up to `src/`). Getting it wrong fails at import time with a bare `Cannot find module '.../logger.ts'` and no hint of the correct depth — copy the import from a sibling hook at the same depth.
