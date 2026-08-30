---
date: 2026-06-16
keywords: ["devbot", "tool", "schema", "opencode", "args"]
---

## All devbot tool .ts files use args: tool.schema.object({}) for parameterless tools

Canonical pattern for OpenCode tools without typed parameters is `args: tool.schema.object({})`, as used in several built-in modules. Previously tools used `args: {}` (plain object). `tool.schema.object({})` is the SDK's built-in schema DSL — equivalent behavior but explicit about using the schema system. Does not require Zod. The `agentic-tools` script parses `description:` field only (not args), so this change is transparent to tool listing.
