---
date: 2026-08-19
keywords: ["laravel", "eloquent", "observer", "aftercommit", "transactions"]
trigger-on: ["eloquent-observer-aftercommit", "model-observe-aftercommit"]
---

## Eloquent observer $afterCommit is honored by Model::observe(), not ignored

Setting `public bool $afterCommit = true` on an observer IS respected even when the observer is registered via `Model::observe(Observer::class)` in Laravel 13. It looks dead because `HasEvents::registerObserver()` only stores a `"Observer@event"` string listener and never reads the property — but the property is read later, at dispatch time: `Dispatcher::createClassCallable()` resolves the listener and calls `handlerShouldBeDispatchedAfterDatabaseTransactions()`, which checks `$listener->afterCommit` (and requires the `db.transactions` binding to be resolvable) before deferring the call via `DatabaseTransactionsManager::addCallback()`. Only the `creating`/`updating`/`saving`/`deleting`/`restoring`/`forceDeleting` events are deliberately excluded from afterCommit. So deferred-until-commit observers already work out of the box; do not "fix" them by re-dispatching manually.
