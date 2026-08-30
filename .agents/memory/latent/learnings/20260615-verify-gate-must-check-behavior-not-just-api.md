---
date: 2026-06-15
keywords: ["devbot", "verify", "gate", "planning", "code-review"]
---

# VERIFY gate scope: confirm argument-passing mechanism, not just API surface

When a plan's security claim (e.g., "the `$` tag from `@opencode-ai/plugin` eliminates shell injection") depends on an **internal SDK behavior** (e.g., whether it uses `child_process.spawn` with args array vs `child_process.exec` with shell string), the `[VERIFY: gate-*]` marker must confirm that behavior, not just the API surface.

Example: The original `[VERIFY: gate-plugin-api]` marker only checked export shape (.quiet(), .nothrow(), .exitCode). It did not verify the critical security property — is the argument passed as a separate spawn argument or concatenated into a shell string? If `$` concatenates (like `execSync`), replacing `execSync` with `$` is cosmetic only.

Fix: each `[VERIFY: gate-*]` marker must explicitly list:
1. The **property the claim depends on** (e.g., "argument-array spawning, not shell-string concatenation")
2. **How to verify it** (e.g., "read the SDK source to confirm `child_process.spawn` with args array" or "test with `; echo injected` and verify injection payload appears as literal text, not executed")
3. **Why it matters** (e.g., "the entire shell-injection fix depends on this being true")

This applies to any plan-level `[VERIFY: gate-*]` marker where the chain of reasoning passes through an unverified behavior of a third-party dependency. The planner (architect) should include the verification method in the gate description so the implementer knows what to look for.