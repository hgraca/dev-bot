---
date: 2026-04-25
keywords: ["kafka", "consumer", "rdkafka"]
---

## set_error_handler() doesn't work during PHP's final object-destruction phase

During PHP shutdown, after all registered shutdown functions complete, PHP destroys remaining objects. During this phase, `EG(active)` is set to `0` and `zend_error()` bypasses all user error handlers — writing directly to SAPI stderr. `error_reporting()` IS checked before the bypass, so lowering it via `register_shutdown_function` is the only way to suppress C extension destructor warnings (like rdkafka's `rd_kafka_consumer_close`). See `tests/bootstrap.php` for the implementation.
