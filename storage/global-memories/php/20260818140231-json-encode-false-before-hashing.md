---
date: 2026-08-18
keywords: ["php", "json_encode", "sha1", "JSON_THROW_ON_ERROR"]
trigger-on: ["json-encode-hashing"]
---

## json_encode returns string|false — hashing false silently collides

`json_encode()` returns `string|false`, so `sha1(json_encode($obj))` hashes the empty string (`sha1(false)`) when encoding fails, silently colliding unrelated values into one hash. Pass `JSON_THROW_ON_ERROR` (`json_encode($obj, JSON_THROW_ON_ERROR)`) so a failure throws instead, and static analysis then infers `string` — removing the `string|false` baseline noise on downstream `sha1()` calls.
