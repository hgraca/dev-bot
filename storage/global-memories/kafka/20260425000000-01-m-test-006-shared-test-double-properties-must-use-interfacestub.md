---
date: 2026-04-25
keywords: ["kafka", "consumer"]
---

## M-TEST-006: Shared test-double properties must use Interface&Stub, not bare interface

After refactoring KafkaQueueTest and RawMessageInterceptorQueueDecoratorTest to use `createStub()` in setUp, we typed the shared properties as bare interfaces (`NativeKafkaConsumer`, `QueueContract`). PHPStan reported 11 errors because the interface doesn't have `->method()` / `->willReturn()`.
When a shared test property holds a stub, type it as `Interface&Stub` (using `PHPUnit\Framework\MockObject\Stub`). The `initSut()` helper parameter must also use `&Stub`. `MockObject extends Stub`, so passing a mock to a `&Stub` parameter works. Never use the bare interface — PHPStan can't resolve stub methods.
