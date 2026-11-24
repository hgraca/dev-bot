# Worked example

One record and one report, in the shapes `devbot:security-findings` defines. The defect is modelled
on a real class — a record read by sequential id with no tenant check — and the identifiers are
invented. Nothing here is engagement data.

## A source finding

```markdown
**ID:** SEC-2026-11.1
**Title:** Object read by sequential id without a tenant check
**Severity:** High
**CVSS:** 8.1 — CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N
**Tier:** read-in-source
**Finding:** `InvoiceController@show` resolves the record with `Invoice::findOrFail($id)` and returns
it. No policy check and no tenant scope are applied, so the id is the only access control. The route
is behind `auth` middleware, which establishes a session but does not constrain which invoices that
session may read.
**Result:** Any authenticated user reads any tenant's invoice by incrementing the id, including
billing address and line items. Rate limiting slows enumeration but does not prevent it — the ids
are sequential, so the first few guesses succeed.
**Evidence:** AUTH-2026-11.1 — `app/Http/Controllers/InvoiceController.php:44`; the route in
`routes/web.php:71` carries `auth` only; `Invoice` has no global scope and no `tenant_id` filter in
any query builder call in the controller.
**Status:** open
**Discovered:** `4f2a91c` — 2026-11-24
**Location:** `app/Http/Controllers/InvoiceController.php:44` — `InvoiceController::show`
**Recommendation:** Authorise against the record's tenant, not against being logged in — a policy
check in the controller, plus a global scope on `Invoice` so every query carries the boundary. The
global scope is what makes the next controller inherit the fix: a new read path is safe by default
rather than safe once someone remembers.
**References:** CWE-639, A01:2025, ASVS V8.2.1
**Coverage basis:** `devbot:audit-security` §Authorisation — horizontal privilege escalation check
```

## A report

```markdown
# Security review — billing service

## Scope and basis

Source review of the billing service at `4f2a91c`. In scope: `app/`, `routes/`, and the dependency
manifest. Out of scope: the gateway configuration (owned by the platform team), and any runtime
behaviour — no request was made.

## Coverage

| Area                    | Examined        | Basis                                                     |
| ----------------------- | --------------- | --------------------------------------------------------- |
| Authorisation           | `app/Policies`, `app/Http/Controllers` | Read + call-graph trace to the sink        |
| Injection               | `app/Repositories` | `semgrep --config p/php` + manual trace                |
| Dependencies            | `composer.lock` | `trivy fs` — ran                                          |
| Security headers        | not examined    | runtime only — needs an observation, see the pentest skill |
| Session configuration   | not examined    | tool absent: `bandit` does not cover PHP; no equivalent run |

## Findings

### High — 1

SEC-2026-11.1 · Object read by sequential id without a tenant check · 8.1

## Refutation

| ID            | Verdict    | Rested on                                                                 |
| ------------- | ---------- | ------------------------------------------------------------------------- |
| SEC-2026-11.1 | uphold     | Refuter traced two other callers; both reach the same unscoped query.      |

## Summary

| Severity | Count |
| -------- | ----- |
| High     | 1     |

**Top three:** SEC-2026-11.1.
**Quick wins:** none — the fix is a policy plus a scope, not a one-line change.
**Systemic:** the model layer has no tenant boundary at all; SEC-2026-11.1 is one instance of it.

## Positive findings

- Prepared statements throughout the repository layer; no string interpolation into SQL found.
- Password hashing uses `password_hash()` with argon2, and session ids regenerate on login.
```

## What the example demonstrates

- The `Tier` is `read-in-source` and `Result` does not claim an observed exploit.
- The `CVSS` vector sets no Threat or Environmental metrics, because a source review cannot observe
  the deployment.
- Coverage names two areas that were **not** examined and why. A reader can tell this review is
  partial without reading a disclaimer.
- The refutation column is filled per finding — a report with an empty refutation section has not
  been refuted, it has been written.
