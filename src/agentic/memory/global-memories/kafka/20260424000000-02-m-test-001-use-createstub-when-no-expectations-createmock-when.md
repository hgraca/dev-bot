---
date: 2026-04-24
keywords: ["kafka", "consumer"]
---

## M-TEST-001: Use createStub() when no expectations, createMock() when expectations exist

6 tests in KafkaConsumerTest used `createMock()` for test doubles that only configured return values (no `expects()` calls). PHPUnit generated notices about mock objects without expectations.
Always use `$this->createStub()` when the test double only needs `method()->willReturn()`. Reserve `$this->createMock()` for when you call `expects()`. This eliminates PHPUnit notices and makes test intent clearer.
