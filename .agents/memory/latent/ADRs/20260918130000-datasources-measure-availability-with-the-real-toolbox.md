---
date: 2026-09-18
keywords: ["datasources", "mcp-toolbox", "availability", "oracle", "quarantine"]
see: ["ADRs/20260917204927-datasources-gateway-host-network-generated-compose.md"]
---

## Measure datasource availability with the real toolbox, never predict it with a probe

The `datasources` module used to decide which sources to publish by probing — a bare TCP connect-and-close per declared datasource every 10s. That probe blocked the production MariaDB host (each dial counts as a handshake abort against `max_connect_errors`), and because a blocked host still completes TCP the probe kept reporting the poisoned source as usable, so the block was self-sustaining; the same run let a transient empty render `cp` over a good gateway config and erase every toolset.

**Decision:** devbot opens no database connection of its own. Candidacy is env-completeness only (no socket). Availability is **measured** by running the pinned toolbox image once against the candidate config as a throwaway canary (readiness = `/healthz`); the toolbox fails fast and names the source it cannot initialize, so the validator drops that source and retries, bounded by the catalogue size. Rejected sources are parked in `storage/datasources/quarantine.json` on an exponential backoff (10s → 5min, a MariaDB-blocked host 30min), the publish is skipped when nothing changed, and a published config is verified against the running gateway and rolled back only if the reload is rejected twice (a single rejection can be a partial read of the in-place `cp`).

**Why it wins:** the filter's invariant — "a published source is one the gateway can initialize" — becomes true by construction rather than a hopeful proxy; the only connections spent are the real client's authenticated ones, which neither advance nor preserve a host block; and no devbot code has to speak any database protocol. **Cost:** validation costs one container run per candidate change (backoff-gated), and it depends on docker plus the pinned image's `/healthz` and error-string contract.
