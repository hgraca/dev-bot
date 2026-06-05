---
date: 2026-06-28
keywords: ["laravel", "serialization", "queue", "throwable", "closure"]
trigger-on: ["queue-serialization", "throwable-dto", "failure-reason"]
---

## Throwable in DTO fails queue serialization due to Closure in backtrace

DTOs containing `Throwable` (Exception) objects fail when dispatched through Laravel's queue. The queue calls `serialize(clone $job)` on the EventEnvelope, which traverses the entire object graph. Exception backtraces in PHP 8.4 can contain Closure references that are not serializable. Fix: implement `__serialize()`/`__unserialize()` on the DTO to preserve the exception message as a string and reconstruct as `\RuntimeException` on deserialization. The same issue applies to any queue-dispatched job containing Throwable objects — they must be serializable. Applies to both sync and async queues.
