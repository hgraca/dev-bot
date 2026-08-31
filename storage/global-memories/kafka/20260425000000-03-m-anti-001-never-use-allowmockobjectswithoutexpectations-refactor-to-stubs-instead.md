---
date: 2026-04-25
keywords: ["kafka"]
---

## M-ANTI-001: Never use #[AllowMockObjectsWithoutExpectations] — refactor to stubs instead

KafkaQueueTest and RawMessageInterceptorQueueDecoratorTest had 11 `#[AllowMockObjectsWithoutExpectations]` attributes suppressing PHPUnit notices on shared mocks. This hid the real problem: mocks were used where stubs would suffice.
`#[AllowMockObjectsWithoutExpectations]` suppresses the symptom, not the cause. When a shared mock triggers "no expectations configured" notices, refactor: use `createStub()` in setUp, extract `initSut()` helper, create a local `createMock()` only in tests that call `expects()`. This is now codified in the `phpunit` skill.

## See also

- [[key_decisions]]
- [[patterns]]
- [[gotchas]]
