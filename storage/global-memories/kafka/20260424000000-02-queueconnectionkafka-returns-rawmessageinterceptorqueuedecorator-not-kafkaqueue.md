---
date: 2026-04-24
keywords: ["kafka"]
---

## Queue::connection('kafka') returns RawMessageInterceptorQueueDecorator, not KafkaQueue

When resolving `Queue::connection('kafka')`, Laravel's QueueManager wraps the real KafkaQueue in a `RawMessageInterceptorQueueDecorator`. This means typed property assignments like `KafkaQueue $queue = Queue::connection('kafka')` will fail at runtime. Use local variables with `@var` annotations instead.
