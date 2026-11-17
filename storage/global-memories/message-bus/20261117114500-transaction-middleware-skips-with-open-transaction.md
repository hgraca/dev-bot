---
date: 2026-11-17
keywords: ["message-bus", "transaction-middleware", "transactions", "nested-transactions"]
aliases: ["handler wrapped in a transaction", "RequiresNestedDbTransaction", "max_nested_transactions"]
trigger-on: ["message-bus-handler-transaction", "message-bus-middleware-config"]
---

## The transaction middleware skips when a transaction is already open

`TransactionMiddleware` wraps each command and event handler in a DB transaction, but only when
`$connection->transactionLevel() <= max_nested_transactions` — otherwise it logs "Transaction already
started, skipping opening a nested transaction" and runs the handler inside the **caller's**
transaction. So "the middleware is configured" means the handler runs in a transaction, not that it
owns one: a failed handler rolls back everything the caller did, and PHPUnit's per-test transaction
changes the behaviour (`transaction.max_nested_transactions` defaults to `0`; a project sets `1` in
test environments). A message implementing `RequiresNestedDbTransaction` bypasses the skip and gets
an inner transaction regardless.

It is the last entry of `CommandBusServiceProvider::DEFAULT_SYNC_MIDDLEWARES` and
`DEFAULT_ASYNC_EXECUTION_TIME_MIDDLEWARES`, and of
`EventBusServiceProvider::DEFAULT_EXECUTION_TIME_MIDDLEWARES`; the query bus has none. Configured is
not the same as active: `agent-service` substitutes `LongRunningCommandTransactionMiddleware`, which
delegates to the real middleware for every command except `ExecuteAgentRun`. A host that *assigns* a
middleware list replaces the default wholesale — `MessageBusServiceProvider::mergeConfigs()` gives a
numeric list the win, including `[]` — so verify the resolved list rather than the presence of a
`config/message_bus.php`. Dispatch-time lists never carry the wrapper.
