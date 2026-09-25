---
date: 2026-09-24
keywords: ['laravel', 'message-bus', 'aftercommit', 'queue', 'transactions']
trigger-on: ['message-bus-async-dispatch', 'queue-after-commit']
---

## message-bus async commands are after-commit by default — the connection's after_commit flag is irrelevant

`get-e/message-bus`'s `AsyncCommandDispatcher::dispatchAsync()` stamps every command that does not implement `AlwaysDispatchableMessage` with `$envelope->afterCommit()` (the envelope uses Laravel's `Queueable` trait), so an async bus command is pushed to the queue only after the outermost DB transaction commits — and `Illuminate\Queue\Queue::enqueueUsing()` additionally registers a rollback callback that discards the pending command if the transaction rolls back. The connection-level `after_commit` flag (deliberately `false` on the message-bus Redis connections and validated at boot by `MessageBusServiceProvider`) never decides this: `Queue::shouldDispatchAfterCommit()` returns the job-level `$job->afterCommit` value _before_ falling back to `$this->dispatchAfterCommit`. So dispatching a bus command from inside an Eloquent observer or a model save is already transaction-safe — do not add a manual `DB::afterCommit()` wrapper or a deferred-dispatch workaround, and do not "fix" it by
swapping one async method for another. The exception is a plain Laravel job (not a bus command): it carries no per-envelope flag and therefore needs `ShouldQueueAfterCommit` (or `$this->afterCommit = true`) to avoid queueing before commit on a connection with `after_commit=false`. Implement `AlwaysDispatchableMessage` on a bus command only when it genuinely must dispatch regardless of the transaction outcome.
