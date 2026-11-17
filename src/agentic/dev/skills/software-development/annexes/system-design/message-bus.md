---
name: message-bus
description: "Message bus and CQRS design rules that hold in any stack: transaction boundaries around handlers, delivery guarantees, idempotency, and where the middleware pipeline sits. Read this annex whenever a project dispatches commands, events or queries through a bus."
---

# Message Bus

## When to Apply

- A project dispatches commands, events, or queries through a bus, in any language or framework
- Writing, changing, or reviewing a command handler, event listener, or query handler
- Reading or changing a bus configuration, including its middleware pipeline
- Designing a workflow whose steps are messages rather than calls

## Annex of `devbot:software-development`

This file is an annex of the `devbot:software-development` hub. For generic craft — code-quality
principles, tests-first discipline, commit protocol — see `devbot:software-development`. Concrete
configuration keys, classes, and test tooling for the `get-e/message-bus` package are in the
[PHP annex](../php/message-bus.md).

## No assumptions about the bus

The bus is configuration plus convention, and both are project-local. Before relying on any
behaviour, establish it from the project's configuration — and from the framework or package default
it falls back to when the project does not set it. Never infer it from another project, from a
sibling service, or from the framework's usual way of doing things. Record what you established.

Establish, at minimum:

| Question                                                   | Why it changes the code you write                           |
| ---------------------------------------------------------- | ----------------------------------------------------------- |
| Which messages are handled in-process, which over a broker | Determines failure modes, retries, and latency              |
| Is delivery at-most-once, or at-least-once                 | At-least-once demands idempotent handlers and deduplication |
| Is ordering guaranteed, and on what key                    | Aggregates can receive out-of-order state changes otherwise |
| Is the handler wrapped in a transaction, and by what       | Sets the rollback scope — see below                         |
| What retries, backoff, and dead-lettering apply            | Decides whether a handler may be non-idempotent             |

## Transactions (MUST verify)

Handlers are usually expected to execute inside a transaction opened by a middleware that wraps
them — a message handler is one unit of work against the datastore. That is the default setup, not a
guarantee. Verify it before writing, changing, or reviewing a handler, and never assume it either
way.

A middleware pipeline is configuration, so a project can lose the wrapper without anyone noticing:

- **A configured list may replace the default, or merge with it.** Configuration systems differ:
  some replace a list wholesale when the project sets it, some merge or append. Read _how this
  project's lists are composed_ — and what the resolved list actually contains — before concluding
  that a default entry is present or lost. A project can also legitimately drop one deliberately.
- **Configured is not the same as wrapping.** A substituted or decorated middleware may delegate to
  the real one for most messages and bypass it for a chosen few.
- **Dispatch-time and execution-time pipelines are different.** The list that runs when a message is
  _dispatched_ carries logging, context, and lifecycle concerns; the list that runs when a message is
  _handled_ is where a transaction wrapper belongs. Look in both.
- **An already-open transaction may suppress the wrapper.** Many implementations skip opening a
  nested transaction when the caller already has one, so a handler invoked from an HTTP request or
  from another handler joins the caller's transaction instead of owning one. Whether that is
  configurable, and how a message opts into its own savepoint, is implementation-specific — read it.

Consequences once the answer is known:

- **Wrapped** — do not open a transaction inside the handler, and expect a failure to roll back
  everything the caller did in that transaction, not just the handler's writes. Long-running work
  (external calls, waits, a job measured in minutes) must not hold that transaction open at all.
- **Not wrapped** — surface it as a pre-existing issue, naming the handler that relies on atomicity,
  and ask before changing the bus configuration: the middleware alters every handler's behaviour,
  which is a decision, not a fix.

## Handler-level rules

- **Idempotency follows from delivery.** At-least-once means a handler will see the same message
  again; design for it, and deduplicate on the message id rather than assuming a single delivery.
- **Derive behaviour from persisted state, not from a flag carried on one message.** A lost or
  retry-exhausted message otherwise loses the intent with nothing left to notice it.
- **Check-then-act is not atomic.** An existence check followed by an insert races; convert the
  resulting constraint failure into the intended domain outcome instead of letting it retry forever.
- **A failure must leave a trace a human can act on.** Log the message identity, the attempt number,
  and the reason at a level that reaches whoever owns the service.
- **Side effects that must survive a rollback need a record inside the transaction** — an outbox row
  written with the state change, with the actual dispatch performed after it commits.

## See also

- `annexes/php/message-bus.md` — the `get-e/message-bus` package: keys, classes, handler templates
- `devbot:software-development` — the hub
