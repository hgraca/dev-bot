---
date: 2026-09-25
keywords: ["kafka", "rdkafka", "phpunit", "test-double"]
trigger-on: ["rdkafka-test-double"]
---

## php-rdkafka's `Message` and consumer classes can be stubbed — check finality before assuming otherwise

`createStub(RdKafka\Message::class)` works, and its public properties (`topic_name`, `partition`, `offset`, `headers`) can be set on the stub, so a class under test that accepts an `RdKafka\Message` is directly unit-testable. A comment in a codebase like "requires a C-extension class in its constructor, so it cannot be doubled" may be about a **`final`** class in your own code — for example a `final readonly KafkaProducer` — rather than about rdkafka's types. Establish _why_ something is undoubleable (final? no constructor injection? genuinely unreflectable?) before designing a test around that assumption, because it can push you into an unnecessary live-broker integration test. One caveat when stubbing rdkafka consumers: the extension calls `rd_kafka_consumer_close()` during GC and emits a `Local: Fatal error` warning on a stub with no real connection — suppress that specific string with `set_error_handler`, as the message-bus suite does.
