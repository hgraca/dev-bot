---
name: devbot:find-sentry-issues
description: Find the production issues worth fixing — rank open Sentry issues by user impact, pull full context (stack trace, release, affected users, surrounding events), map each to the offending code, and produce a delegation-ready inventory
---

Find every category of production issue visible in Sentry, then produce a delegation-ready inventory. Rank by **user impact**, not raw event count — a 10k-event crash swallowed by a retry loop matters less than a 50-event checkout failure.

**Technology mapping — the method is stack-agnostic; names below are the current stack used as examples, substitute your own equivalents:**

- **Sentry MCP** — the hosted endpoint wired by this module (`https://mcp.sentry.dev/mcp`). Discover the exact tool names from the connected server before starting: the tool set is defined by the server and changes upstream, so read the tool list rather than assuming names. The capabilities you need are: search/list issues, fetch one issue's detail, fetch the events of an issue, and fetch a release's context.
- **Source access** — the repository the stack trace points at, so a finding names a file and symbol, not just an exception type.
- **Release/deploy context** — the release the issue first appeared in, to separate a regression from long-standing noise.

If `SENTRY_ACCESS_TOKEN` is not set, stop and say so — the server will connect but every call fails. Add the token to your shell profile and start devbot from a new terminal.

## 0. Establish scope before listing anything

Do not start from "all issues ever". Fix the window and the environment first, or the ranking is meaningless.

- Pick the window (e.g. last 24h / 7d / since the last release).
- Pick the environment (`production` — never mix in staging, it doubles the volume with non-actionable noise).
- Note the project(s) in scope. If the org has many, ask which this work targets rather than sweeping all of them.

Record the scope at the top of the report — every number below is only meaningful relative to it.

## 1. Rank by user impact, not event count

Pull the issue list for the window and sort by **users affected**, then by events. For each candidate record:

| Field                  | Why it matters                                                                 |
| ---------------------- | ------------------------------------------------------------------------------ |
| Users affected         | The actual blast radius — the primary sort key                                 |
| Events                 | Volume; useful only alongside users (high events + few users = one retry loop) |
| First seen / last seen | A new `first seen` inside the window is a regression                           |
| Release                | Ties the issue to a deploy                                                     |
| Trend                  | Rising spikes are more urgent than flat long tails                             |

Classify each as exactly one of:

- **Crash / unhandled exception** — the user's action failed outright.
- **Handled but wrong** — no exception surfaced, but the outcome was incorrect (silent data loss, wrong value).
- **Performance regression** — slow, not failing (route/query timings).
- **Noise / non-actionable** — third-party, bot traffic, already-mitigated. Say so explicitly rather than dropping it silently.

## 2. Pull full context for each ranked issue

For every issue above the cutoff, fetch the detail and at least one representative event. Collect:

- The **stack trace**, with in-app frames distinguished from vendor/library frames. The first in-app frame is the finding's anchor.
- The **release and environment**, to place it relative to deploys.
- **Breadcrumbs / request context** if available — the user action that preceded it.
- The **event count vs user count** ratio, to confirm it is not a single user looping.
- **Tags** that segment the impact (browser, OS, route, tenant).

Do not read a stack trace and stop there — the same symptom can come from several code paths, so check whether the events cluster into distinct traces.

## 3. Map each finding to code

For each surviving issue, locate the offending code in the repository:

- Trace the top in-app frame to its file and symbol.
- Determine whether the failure is a **logic bug**, a **missing guard** (null/empty/absent field), an **API/contract mismatch**, a **resource limit** (timeout, memory, connection pool), or **configuration**.
- Note the fix surface: which file, which function, roughly how contained the change is.
- If the code path no longer exists on the current branch, mark the issue **already-fixed / stale** and say which commit retired it — do not spend effort on it.

## 4. Rank the inventory and write it back

Produce a table, ordered by impact, with one row per finding:

| #   | Issue | Class | Users | Events | Release | Root cause | Fix surface |
| --- | ----- | ----- | ----- | ------ | ------- | ---------- | ----------- |

Then, under the table:

- **Top 3 to fix now** — the ones worth a ticket today, each with a one-line justification tied to user impact.
- **Worth monitoring** — plausible but not yet proven to affect users.
- **Explicitly deprioritised** — with the reason (noise, third-party, already fixed), so the next reader does not re-triage them.

Write the report next to the work it belongs to, and open backlog items for the "fix now" set rather than fixing inline — this command's job is the inventory, not the patch.
