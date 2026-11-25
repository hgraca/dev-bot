---
name: devbot:audit-security
description: "Use when performing a security review, building a threat model, or assessing a source tree for vulnerabilities. Triggers on 'STRIDE', 'OWASP', 'CWE', 'threat model', 'security audit', 'authorisation check', 'dependency audit', 'hardcoded secrets'."
---

# Web Application Security Review Methodology

## When to Apply

- Performing security review of web application code
- Building threat model for feature or system
- Auditing authentication or authorisation systems
- Reviewing dependencies for vulnerabilities
- Evaluating code for OWASP Top 10 vulnerabilities

## Before You Start

1. Read architecture document — understand system boundaries and data flows
2. Identify trust boundaries: where does external data enter?
3. Clarify scope: what system, feature, or module being reviewed?
4. Check past security findings — have similar issues been found before?

## 1. Threat Modelling (Before Code Review)

Use STRIDE to systematically identify threats:

| Category                   | Question                                                   |
| -------------------------- | ---------------------------------------------------------- |
| **S**poofing               | Can attacker impersonate legitimate user or system?        |
| **T**ampering              | Can data modified in transit or at rest without detection? |
| **R**epudiation            | Can user deny having performed action?                     |
| **I**nformation Disclosure | Can sensitive data accessed by unauthorized parties?       |
| **D**enial of Service      | Can system made unavailable to legitimate users?           |
| **E**levation of Privilege | Can user gain higher permissions than intended?            |

Threat modelling is also where **A06 Insecure Design** is answered: a system with no threat model,
or one whose design permits a limit to be bypassed rather than merely mis-implementing it, is a
finding in its own right.

### Threat Model Output Format

```
**Asset:** <what at risk>
**Threat:** <STRIDE category — specific threat>
**Likelihood:** High / Medium / Low
**Impact:** High / Medium / Low
**Current controls:** <what exists>
**Gap:** <what missing>
**Recommendation:** <specific action>
```

**Exit:** every trust boundary has at least one threat, and every threat names either an existing
control or a gap with a recommendation. A threat model that lists threats without controls is a wish
list.

## 2. OWASP Top 10:2025

The publisher is the authority — take the numbering and the category names from
<https://owasp.org/Top10/2025/>, never from a second-hand summary. Its own framing is **two new
categories and one consolidation**, so a reader reconciling a 2021 checklist renumbers rather than
duplicates:

| #   | Category                                                | What it looks like in source                                                    |
| --- | ------------------------------------------------------- | ------------------------------------------------------------------------------- |
| A01 | Broken Access Control                                   | Missing authorisation on a route or object; IDOR; path traversal; SSRF; CSRF    |
| A02 | Security Misconfiguration                               | Debug on in production; default credentials; permissive CORS; missing headers   |
| A03 | **Software Supply Chain Failures** _(expands A06:2021)_ | Unpinned dependencies; install scripts; unsigned artifacts; unpinned CI actions |
| A04 | Cryptographic Failures                                  | Weak hashing; hardcoded keys; absent transport encryption; weak randomness      |
| A05 | Injection                                               | SQL, command, LDAP, template and header injection; XSS                          |
| A06 | **Insecure Design** _(was A04:2021)_                    | No threat model; unlimited consumption; limits enforced only in the client      |
| A07 | Authentication Failures                                 | Credential-stuffing exposure; session fixation; weak reset flows                |
| A08 | Software or Data Integrity Failures                     | Deserialising untrusted data; trusting an artifact without verification         |
| A09 | Security Logging and Alerting Failures                  | Sensitive operations unlogged; no actor in the log; no alerting path            |
| A10 | **Mishandling of Exceptional Conditions** _(new)_       | Fail-open error handling; stack traces to users; unhandled exhaustion           |

Two categories were folded away and must not be checked under their own heading: **XSS belongs to
A05** and **SSRF to A01**. A checklist that still lists them separately is answering a list OWASP
stopped publishing — and it chases them while missing A03, A06 and A10 entirely.

## 3. Language-Specific Checklists

The categories above are universal; the checklists below map them to concrete, language-specific
checks. Run the checklist for every language the project uses.

A language with no section here gets the category table above and an explicit line in the report
saying no language-specific checks were applied. Silence reads as coverage.

**Exit:** every category A01–A10 is recorded as `checked`, `clean`, `not applicable` (with the reason)
or `not examined` (with the reason). The last two are the ones that get skipped, and they are the ones
a reader needs.

### PHP

#### A04 — Cryptographic Failures

§2's A04 row names four signs, and this section checks all four — with two splits. **Password**
hashing is A07's, because that is where the authentication checklist lives; this section covers every
other use of a hash. **Transport headers** are A02's; what is checked here is whether verification is
enforced at all.

- [ ] Symmetric encryption uses an authenticated mode — GCM, or libsodium's `secretbox` — never ECB,
      and never CBC without a MAC
- [ ] Every encryption generates a fresh random IV or nonce; none is constant, reused across calls, or
      derived from the key
- [ ] Keys come from the environment or a secret store — never a committed config file, the code, or
      the raw user password
- [ ] Security-relevant randomness uses `random_bytes()` or `random_int()` — not `rand()`,
      `mt_rand()`, or `uniqid()`
- [ ] TLS verification is never disabled: no `CURLOPT_SSL_VERIFYPEER => false`, no
      `CURLOPT_SSL_VERIFYHOST => 0`, no HTTP-client `verify => false`
- [ ] Every call carrying credentials or personal data uses TLS with a floor of 1.2 — no `http://`
      endpoint, and no client permitted to negotiate below it
- [ ] Integrity is verified with an authenticated mechanism — an AEAD tag, libsodium's `secretbox`
      or `crypto_auth`, or `hash_hmac()` with a current algorithm — never a bare `hash()`; digests
      compare with `hash_equals()`, not `==`
- [ ] Hashes outside password storage — integrity checks, cache keys, lookup digests — use a current
      algorithm, with a salt where the input is guessable; MD5 and SHA-1 are never sufficient
- [ ] A decryption failure is handled as a failure — a `false` return is never treated as plaintext
- [ ] Data that needs encryption at rest (PII, credentials, tokens) is encrypted where it is stored,
      not only in transit

#### A05 — Injection

- [ ] All SQL queries use prepared statements or parameterised queries
- [ ] No use of `$_GET`, `$_POST`, `$_REQUEST` directly in queries
- [ ] ORM queries use bound parameters (no raw string interpolation)
- [ ] Shell commands use `escapeshellarg()` / `escapeshellcmd()`
- [ ] LDAP queries use `ldap_escape()`
- [ ] XML input uses `libxml_disable_entity_loader(true)`

#### A05 — Cross-Site Scripting (XSS)

- [ ] All output in templates escaped: `htmlspecialchars()` or template engine equivalent
- [ ] Content Security Policy headers set
- [ ] DOM manipulation does not use `innerHTML` with user data

#### A01 — Cross-Site Request Forgery (CSRF)

- [ ] All state-changing endpoints (POST/PUT/PATCH/DELETE) have CSRF tokens
- [ ] CSRF token validated on server side, not just client side
- [ ] `SameSite=Strict` or `SameSite=Lax` on session cookies

#### A01 — Authorisation

- [ ] Every endpoint checks authorisation — not just authentication
- [ ] Vertical privilege escalation: can regular user access admin functions?
- [ ] Horizontal privilege escalation: can user A access user B data?
- [ ] Direct object references use indirect references or authorisation checks
- [ ] Server-side requests to a user-supplied URL are allowlisted by host, not blocklisted
- [ ] A redirect from an allowlisted host cannot reach an internal address
- [ ] Loopback, link-local and metadata endpoints (`169.254.169.254`) are unreachable

#### A01 — File Handling

- [ ] Uploaded files validated by content type, not just extension
- [ ] Upload directory outside webroot or has no execute permissions
- [ ] Filenames sanitised before storage
- [ ] Path traversal: `../` sequences removed from file paths

#### A07 — Authentication and Session

- [ ] Passwords hashed with `password_hash()` (bcrypt/argon2), not MD5/SHA1
- [ ] Session ID regenerated after login (`session_regenerate_id(true)`)
- [ ] Session timeout configured
- [ ] Secure + HttpOnly + SameSite flags on session cookies
- [ ] Login attempts rate-limited
- [ ] Password reset tokens single-use, time-limited, invalidated on use

#### A03 — Software Supply Chain

- [ ] `composer audit` run — no known CVEs in dependencies
- [ ] Outdated packages with security patches noted
- [ ] No abandoned packages in production dependencies
- [ ] A lockfile is committed, and CI installs from it
- [ ] Dependencies are pinned — a range that resolves differently each install is a gap
- [ ] Composer install scripts and plugins are reviewed, not merely declared
- [ ] CI actions are pinned by commit SHA, not by tag

#### A06 — Insecure Design

Design gaps that correct implementation cannot fix. Check these against the threat model from §1,
not against a diff.

- [ ] A threat model exists, and the code reflects its trust boundaries
- [ ] Business limits enforced server-side: quantity, frequency, total, and per-account caps
- [ ] No security decision delegated to the client — hidden fields, disabled inputs, JS checks
- [ ] Rate and resource limits where the design creates a cheap attack: enumeration, reset, search
- [ ] A workflow cannot be skipped by calling a later step directly
- [ ] Re-authentication required before a change that makes the account less safe

#### A02 — Configuration

- [ ] `display_errors = Off` in production
- [ ] `expose_php = Off`
- [ ] Debug/development tools disabled in production
- [ ] Environment variables used for secrets, not config files

#### A02 — Headers

- [ ] `Strict-Transport-Security` (HSTS) configured
- [ ] `X-Frame-Options: DENY` or `SAMEORIGIN`
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `Referrer-Policy` configured
- [ ] `Permissions-Policy` configured

#### A08 — Software or Data Integrity

- [ ] `unserialize()` is not called on data that crossed a trust boundary; if it is, `allowed_classes` is set
- [ ] No signed or encrypted payload is accepted without verifying the signature
- [ ] Release artifacts, images and migrations are verified before use
- [ ] CI configuration cannot be changed by an unreviewed pull request from a fork
- [ ] No `eval()` or dynamic `include` of a path that carries user input

#### A09 — Security Logging and Alerting

- [ ] Authentication successes and failures, authorisation denials and privilege changes are logged
- [ ] Each entry carries the actor, action, object, outcome and a timestamp
- [ ] Credentials, tokens and personal data do not reach the log
- [ ] Logs have retention, and an alert path exists for the events that matter
- [ ] No suppression rule can silence a whole category of security event

#### A10 — Mishandling of Exceptional Conditions

- [ ] A `catch` block never fails open — an exception in an authorisation path denies, not allows
- [ ] User-facing errors carry no stack trace, query, path or internal identifier
- [ ] Every external call has a timeout, and its failure path is defined
- [ ] Resource exhaustion (memory, disk, connections, recursion) is bounded
- [ ] A partially completed write rolls back, or is recoverable
- [ ] Error handling cannot distinguish an existing account from a missing one

#### Quick Scan Commands (candidate generators)

These find _candidates_ — a sink, a call, a string in the source. A hit is not a finding: `grep`
cannot tell whether attacker-controlled input reaches the sink, or whether a guard sits in front of
it. Run them to build a list to trace, never a list to report.

**Confirming a candidate** — all three, or it stays a candidate:

1. **Reachability** — trace from an untrusted boundary (a request, a file, a queue message) to the
   sink. If no path exists there is no finding; record that you checked and drop it.
2. **Guard** — check what runs on the _release_ path, not in a test or a dev config. A middleware
   registered conditionally is not a guard, and a validated field is not validated on every caller.
3. **Evidence** — record the path, with `Location` for both the boundary and the sink. A finding that
   names only the sink has shown a dangerous function, not a vulnerability.

Prefer a semantic pass to `grep` where one is available: `semgrep` matches the shape of a call rather
than a string, and the `codebase-memory` call graph answers "who can reach this" directly. See
`devbot:security-findings` for why an untraced candidate is not a finding.

`semgrep`, `gitleaks` and `trivy` are provisioned by the module's tooling façade —
`$DEV_BOT_ROOT/src/agentic/security/scripts/tooling.sh` (`DEV_BOT_ROOT` is the dev-bot checkout;
a consumer project does not carry this path). Run them through `tooling.sh run <tool>`, and ask
`tooling.sh check` what is present: a tool that is absent is a check that did not run, and the
coverage table says so rather than passing it silently.

```bash
# Find all direct DB queries (check for parameterisation)
grep -rn "mysql_query\|mysqli_query\|\$pdo->query\|\$db->query" \
  --include="*.php" --exclude-dir=vendor .

# Find all eval() usage (high risk)
grep -rn "eval(" --include="*.php" --exclude-dir=vendor .

# Find all unserialize() (high risk)
grep -rn "unserialize(" --include="*.php" --exclude-dir=vendor .

# Find all file includes with variables (LFI risk)
grep -rn "include\|require" --include="*.php" --exclude-dir=vendor . \
  | grep "\$"

# Check password hashing (should see password_hash, not md5/sha1)
grep -rn "md5\|sha1" --include="*.php" --exclude-dir=vendor . \
  | grep -i "pass"

# Find raw superglobal usage in queries
grep -rn "\$_GET\|\$_POST\|\$_REQUEST\|\$_COOKIE" \
  --include="*.php" --exclude-dir=vendor . \
  | grep -i "query\|sql\|where\|select\|insert\|update\|delete"

# Dependency audit
composer audit 2>/dev/null || echo "composer audit not available"

# Search for hardcoded secrets
grep -rn "password\|secret\|api_key\|token\|credential" \
  --include="*.php" --include="*.env" --include="*.json" \
  --exclude-dir=vendor --exclude-dir=node_modules . \
  | grep -v ".env.example" | grep -v "test"

# Check git history for accidentally committed secrets
git log --all --full-history -- "*.env" "*.key" "*.pem"
```

## 4. Authentication and Authorisation Deep-Dive

When reviewing auth systems:

1. **Map full auth flow** — where does user prove identity?
2. **Map full authz flow** — where does system check permissions?
3. **Test escalation paths** — what happens if you skip step?
4. **Check token lifecycle** — created, validated, refreshed, invalidated
5. **Check multi-tenancy** — any path where tenant A can reach tenant B?

**Exit:** every step of both flows is located in the code, and every escalation path you tried is
recorded with its result. An escalation path you did not try is not a clean result.

## 5. Scoring

Score with **CVSS v4.0**, in the record `devbot:security-findings` defines — it owns the scheme, the
bands, the lifecycle and the report shape, and none of it is restated here.

A source review sets the **Base** metrics only. It cannot observe the deployment, so Threat and
Environmental metrics stay unset, and `Tier` records that the evidence is `read-in-source`. That
combination is the honest one: a base score on traced code paths, with no claim about what an
attacker will actually meet.

## 6. Writing the finding

Use `devbot:security-findings`'s record. Two fields carry what a source review can supply and a
runtime test cannot: `Location` — `path:line` plus the enclosing symbol — and `Coverage basis`, which
check produced it.

Then write it to the store with
`$DEV_BOT_ROOT/src/agentic/security/scripts/findings.sh add` — `DEV_BOT_ROOT` is the dev-bot
checkout, and the script is not on `PATH`. A finding that exists only in the report cannot be gated,
and a finding nobody gates is one the next person re-introduces.

## 7. Coverage

A review that does not say what it did not look at cannot be told apart from a partial one. Record
coverage before findings, not after: the two are read together, and the findings mean nothing without
the boundary around them.

| Area          | Files or modules            | Result                                          |
| ------------- | --------------------------- | ----------------------------------------------- |
| Authorisation | `app/Policies`, controllers | checked                                         |
| Injection     | repository layer            | clean                                           |
| Supply chain  | `composer.lock`             | not examined — vendor review has its own ticket |
| Sessions      | —                           | not applicable: no surface                      |

`checked` means the check ran and found something. `clean` means it ran and found nothing. Those are
different claims, and an empty row is neither.

## 8. Re-audit

When reviewing a system that was audited before, work from the prior records and give each one a
verdict:

- **Resolved** — the observable that demonstrated it no longer appears. A commit message, a comment,
  or a stated intention is not the observable.
- **Still open** — the check still fails, under the same record id.
- **Partially resolved** — name what changed and what did not.
- **Not retestable** — name why: the code is gone, the blast radius moved, or the record lacks the
  evidence to re-run it.

Prior records live in the project's vault when `commit_memory` is on; otherwise ask for the last
report rather than assuming there was none.

## 9. Reporting rules

Two rules are this skill's own; the record and the report shape belong to `devbot:security-findings`
and are not repeated here.

- Every source finding carries a `Location` — `path:line` **and** the enclosing symbol, because a
  location without the symbol is a line that moves.
- A candidate that was not traced is not a finding. Say which candidates you dropped and why; the
  coverage table is where that lives.

## 10. Audit summary

The **Summary** section of the shared report shape. What a source review adds to it:

- **Systemic** — a pattern needing an architectural change rather than a point fix is worth more than
  the individual findings it produced. Name it even when no single instance is severe.

## 11. What tends to hide

Defect classes that survive a review because the code looks right where you read it. Use this as a
checklist of what to go looking for, and as the shape a finding should take.

| Symptom                                              | Why the review misses it                                  | What to check instead                                           |
| ---------------------------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------- |
| Authorisation at the route, not per object           | The route gate is visible and looks sufficient            | Trace the identifier into the query and the policy call         |
| A record fetched before the policy check             | The policy call is present, so the line reads as guarded  | Order matters: `find()` first leaks existence via errors        |
| Mass assignment from the request                     | The model looks protected; the guard lives in `$fillable` | Compare every assignable field against what the request carries |
| Escaping applied on input                            | The output looks unescaped, but the input was "cleaned"   | Require output escaping; input cleaning breaks on stored data   |
| Validation that accepts an array for a string field  | The rule name reads correctly                             | Check the type: `field[]=` bypasses a `string` rule             |
| Token comparison with `==`                           | It passes every functional test                           | Require a constant-time comparison                              |
| A check-then-act limit                               | Each half is correct in isolation                         | Look for the window between check and write                     |
| An error path that returns success                   | The happy path is what gets tested                        | Follow every `catch` to its status code                         |
| A console command or queued job bypassing middleware | Middleware is where the team looks for authorisation      | Check every entry point, not just HTTP                          |
