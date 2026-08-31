---
date: 2026-06-15
keywords: ["opencode", "plugin", "dollar-tag", "spawn", "injection", "execSync"]
---

## Verifying `$` tag injection safety requires checking spawn vs exec mechanism

The `$` tagged template literal from `@opencode-ai/plugin` is used in OpenCode plugins for subprocess invocation (e.g., `$`some-binary ${command}``). It is commonly assumed to prevent shell injection because it is a tagged template, but the safety depends on the internal mechanism: tagged template JavaScript separates literal strings from interpolated values, but the implementation can join them into a shell string (`exec`) or pass them as separate spawn arguments (`spawn`). Only the spawn-argument approach prevents shell injection. When relying on `$`for injection safety in a review or plan, the verification gate must explicitly confirm the argument-passing mechanism (spawn with args array), not just the API shape (export name, method signatures). Suggested verification: read the`@opencode-ai/plugin`source to confirm`spawn`-based argument passing, or test with a command containing shell metacharacters and observe whether the metacharacters are escaped/passed literally or interpreted.
