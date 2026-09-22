---
date: 2026-09-22
keywords: ["kafka", "rdkafka", "php-rdkafka-stubs", "Message", "headers"]
trigger-on: ["rdkafka-message-headers", "kwn-php-rdkafka-stubs"]
---

## `RdKafka\Message::$headers` is a property, but kwn's IDE stubs declare it as a method

`kwn/php-rdkafka-stubs` v3.0.1 (already the newest release) models `RdKafka\Message` with a `headers()` **method** and no `headers` property (`stubs/RdKafka/Message.php:59`), so an IDE or LSP flags every `$message->headers` read as `Undefined property '$headers'`. The real extension exposes it as a public property: `ReflectionClass('RdKafka\Message')` against rdkafka 6.0.5 lists `$headers` among the properties and `errstr()` as the only method. Upstream php-rdkafka's own docs are self-contradictory on this — they document `headers()` while their example is `var_dump($message->headers)` — and the changelog entry "Always initialize `Message::$headers`" settles it as a property. So the diagnostic is a stub false positive, not a code bug: `get-e/message-bus` reads `$message->headers` the same way in production. Do not "fix" it by calling `headers()` — that would be a fatal undefined-method call at runtime. Two practical notes: PHPStan is unaffected because the kwn package ships no `autoload` section (it is an IDE-only package, and PHPStan reflects the real loaded extension instead), and the same stub is also broken in the other direction — its `errstr()`/`headers()` bodies return nothing, so static analysis reports "Not all paths return a value" inside vendor.
