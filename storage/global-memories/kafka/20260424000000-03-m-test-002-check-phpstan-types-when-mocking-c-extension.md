---
date: 2026-04-24
keywords: ["kafka", "rdkafka"]
---

## M-TEST-002: Check PHPStan types when mocking C-extension objects

Tests set `$msg->key = null` on `RdKafka\Message` objects. PHP runtime allows it (the property is untyped in the extension), but PHPStan infers `string` from usage patterns and flagged the assignment.
When constructing or configuring C-extension objects in tests (`RdKafka\Message`, etc.), always use values matching the PHPStan-expected types. Use `''` instead of `null` for string-typed properties, even if the runtime accepts null.
