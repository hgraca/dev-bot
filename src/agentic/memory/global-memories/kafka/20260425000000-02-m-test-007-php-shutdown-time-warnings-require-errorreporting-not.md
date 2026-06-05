---
date: 2026-04-25
keywords: ["kafka", "consumer", "rdkafka"]
---

## M-TEST-007: PHP shutdown-time warnings require error_reporting(), not set_error_handler()

rdkafka C extension emits `rd_kafka_consumer_close` warnings when stub KafkaConsumer objects are GC'd at process shutdown. We tried `set_error_handler()` inside `register_shutdown_function()` but the handler was never called.
During PHP's final object-destruction phase, PHP sets `EG(active)=0`, causing `zend_error()` to bypass all user error handlers. `error_reporting()` is checked before that bypass. To suppress C extension destructor warnings at shutdown, use `register_shutdown_function` that lowers `error_reporting()` (e.g., `error_reporting(error_reporting() & ~E_WARNING)`). Place this in a custom PHPUnit bootstrap file.
