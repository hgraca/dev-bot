---
date: 2026-11-06
keywords: ["signoz", "alert-filter", "silencing", "severity-number", "log-noise"]
aliases: ["mute one log message", "exclude log from alert", "per-trip alert silencing", "relegate log level"]
trigger-on: ["signoz-log-alert-silencing", "signoz-per-message-exclusion"]
---

## Silencing one log message on a generic SigNoz alert: exclude it in the rule filter, and date the exception

When a single business failure spams a generic rule, the lever available without pipeline tooling is the
alert rule's own log filter. `Alert-level logs` (`severity_number >= 23`) was flapping 86×/day because
`transfers` retried one ERP invoice every few minutes and each retry emitted **four** lines from the same
correlation id — `WARN` (13, transaction rollback), `ALERT` (23, the exception reporter), `ERROR` (17,
"Command failed (5x)"), `CRITICAL` (21, the terminal handler). Only the `ALERT` line matched `>= 23`, so
triaging "which line trips the rule" means reading `severity_number` per line, not `level_name` per service.

Adding `AND body NOT CONTAINS '<full message text including the entity id>'` to the rule's filter stopped it
(measured 66 → 0 matching lines over 24h, and 0 for every other service, so nothing else was silenced). Two
caveats: SigNoz negative operators (`NOT CONTAINS`, `!=`, `NOT LIKE`, `NOT IN`) also match documents where
the field is absent — benign for inclusion filters like this, dangerous when you meant "present and not X";
and the exception silently desensitises a *generic* production-critical rule, so write the removal date into
the rule `description` and drop a dated vault TODO at the same time. Removing it without fixing the
retrying producer brings the pages straight back.

A log pipeline would reclassify the stored line instead of hiding it from one rule — `severity_parser`
maps `fatal` to number 21, which SigNoz displays as `CRITICAL` — but pipelines are reachable only through
`POST /api/v1/logs/pipelines` with a `SIGNOZ-API-KEY` service-account key; the SigNoz MCP exposes no
pipeline tool, so a session without that key must fall back to the filter exclusion.
