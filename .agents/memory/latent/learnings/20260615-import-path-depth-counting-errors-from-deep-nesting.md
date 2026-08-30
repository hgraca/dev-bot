---
date: 2026-06-15
keywords: ["devbot", "plugin", "import-path", "review"]
---

# Import path depth errors from deeply nested plugin files

Dev-bot plugin files at `src/agentic/<module>/hooks/opencode/<name>.ts` resolve to the project root via 5 `..` levels (`opencode/` → `hooks/` → `<module>/` → `agentic/` → `src/` → project root). A plan for a storage-importing plugin wiring specified 6 levels, which overshoots root by one. The error was masked because the plan's own path trace had an inconsistency in the first step (stayed at the starting directory instead of incrementing). Pattern: when importing from deep plugin nesting, always verify the path by tracing from the **file's directory** to root, counting each `..` transition independently. Use an alternative absolute-path import via `path.join(process.cwd(), ...)` when the project root guarantee exists, which eliminates off-by-one vulnerabilities at the cost of dependency on `process.cwd()` behavior.
