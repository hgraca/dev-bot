---
date: 2026-11-13
keywords: ["phpunit", "audit-log", "message-bus", "nested-dispatch", "assertion"]
trigger-on: ["message-bus-audit-log-test"]
---

## Assert a message-bus audit entry by message class, not by a generic "[INFO] Handling command" substring

A test asserting that a command's audit entry carries its monolog logs must match the message's own line, not the bare phrase: `MessageLogsHandler::$envelope` is a **static** current-envelope, and `EnvelopeLoggerMiddleware` only installs an envelope when none is set, so every nested dispatch (event → listener → command) writes into the **outer** message's log buffer. That buffer is capped (`LoggingMessageEnvelopeTrait::$logMaxRecords`, 200 by default) and evicts from the start, so an entry can contain dozens of nested `[INFO] Handling command …` lines — `assertStringContainsStringIgnoringCase('[INFO] Handling command', $logs)` therefore passes on a nested message's line even when the asserted command's own line is gone, and the test guards nothing. Pin the class instead: `'[INFO] Handling command ' . CommandClass::class`. A related consequence: a standalone event audit record is empty in this harness, because the event middleware chain does not include `EnvelopeLoggerMiddleware` — an event test that asserts `logs[0]` is in fact asserting a nested command's record.
