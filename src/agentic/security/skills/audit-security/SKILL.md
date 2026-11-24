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

## 2. OWASP Top 10:2025

The publisher is the authority — take the numbering and the category names from
<https://owasp.org/Top10/2025/>, never from a second-hand summary. All ten apply to a source review;
the three marked **new** are the ones a 2021-era checklist does not carry at all.

| #   | Category                                          | What it looks like in source                                                    |
| --- | ------------------------------------------------- | ------------------------------------------------------------------------------- |
| A01 | Broken Access Control                             | Missing authorisation on a route or object; IDOR; path traversal; SSRF; CSRF    |
| A02 | Security Misconfiguration                         | Debug on in production; default credentials; permissive CORS; missing headers   |
| A03 | **Software Supply Chain Failures** _(new)_        | Unpinned dependencies; install scripts; unsigned artifacts; unpinned CI actions |
| A04 | Cryptographic Failures                            | Weak hashing; hardcoded keys; absent transport encryption; weak randomness      |
| A05 | Injection                                         | SQL, command, LDAP, template and header injection; XSS                          |
| A06 | **Insecure Design** _(new)_                       | No threat model; unlimited consumption; limits enforced only in the client      |
| A07 | Authentication Failures                           | Credential-stuffing exposure; session fixation; weak reset flows                |
| A08 | Software or Data Integrity Failures               | Deserialising untrusted data; trusting an artifact without verification         |
| A09 | Security Logging and Alerting Failures            | Sensitive operations unlogged; no actor in the log; no alerting path            |
| A10 | **Mishandling of Exceptional Conditions** _(new)_ | Fail-open error handling; stack traces to users; unhandled exhaustion           |

Two categories were folded away and must not be checked under their own heading: **XSS belongs to
A05** and **SSRF to A01**. A checklist that still lists them separately is answering a list OWASP
stopped publishing — and it chases them while missing A03, A06 and A10 entirely.

## 3. Language-Specific Checklists

The categories above are universal; the checklists below map them to concrete, language-specific
checks. Run the checklist for every language the project uses.

A language with no section here gets the category table above and an explicit line in the report
saying no language-specific checks were applied. Silence reads as coverage.

### PHP

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

#### Quick Scan Commands (Safe, Read-Only)

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

## 5. Severity Classification

- **CRITICAL** — Direct exploitation, no authentication required, RCE/SQLi/auth bypass
- **HIGH** — Exploitation requires some access or conditions, data breach risk
- **MEDIUM** — Requires specific conditions, limited impact individually
- **LOW** — Defence in depth, information disclosure, best practice violation
- **INFO** — Observation, no direct risk

## 6. Vulnerability Finding Format

```
**[SEVERITY: CRITICAL/HIGH/MEDIUM/LOW/INFO]**
**Finding:** <title>
**Location:** <file>:<line>
**Description:** What vulnerability is
**Impact:** What attacker can do
**Evidence:** Code snippet or proof of concept (no active exploitation)
**Remediation:** Specific fix with code example
**References:** CVE/CWE if applicable
```

## 7. Reporting Rules

- Never report finding without evidence (code location, line number)
- Always include specific remediation — not just "fix SQL injection" but code example
- Group related findings — do not report 20 instances of same XSS pattern separately
- Always distinguish between confirmed vulnerability and potential risk
- Include positive findings: what codebase does well

## 8. Audit Summary Format

End every review with:

1. **Total findings by severity** — table showing count per severity level
2. **Top 3 most critical items** — three findings needing immediate attention
3. **Quick wins** — easy fixes with high security impact
4. **Systemic issues** — patterns needing architectural change, not just point fixes
5. **Positive findings** — what codebase does well from security perspective
