---
date: 2026-10-05
keywords: ["laravel", "config", "typed-accessor", "invalidargumentexception"]
trigger-on: ["laravel-typed-config-accessor"]
---

## Laravel typed config accessors throw on type mismatch, they do not fall back to the default

`Config::string()`, `Config::integer()`, `Config::boolean()`, `Config::array()`, etc. (backed by `Illuminate\Config\Repository`) return the value only when it matches the requested type; on a mismatch they throw `InvalidArgumentException` ("Configuration value for key [...] must be a string, NULL given"), and the `$default` argument is used only when the key is absent — never when it is present but of the wrong type. The trap: a lookup that reads gracefully in tests (key absent → default, key set to a string) blows up in production where the same key is explicitly `null` or an int. When a value may legitimately be absent *or* explicitly non-string, read it with `Config::get($key)` and narrow yourself (`is_string()`, `is_int()`, …) instead of using the typed accessor.
