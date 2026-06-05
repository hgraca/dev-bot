---
name: audit-security
description: "PHP security review methodology: STRIDE threat modelling, OWASP Top 10, PHP-specific vulnerability checklist, auth deep-dive, dependency audit, structured reporting. Use this skill whenever performing a security review, code audit, threat modelling, or vulnerability assessment on PHP code."
---

# PHP Security Review Methodology

## When to Apply

- Performing security review of PHP code
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

## 2. OWASP Top 10 — PHP Priority Order

1. **Injection** (SQL, Command, LDAP) — most common in legacy PHP
2. **Broken Authentication** — session management, password storage
3. **Broken Access Control** — horizontal and vertical privilege escalation
4. **Security Misconfiguration** — PHP settings, exposed debug info
5. **Cryptographic Failures** — weak hashing, hardcoded secrets
6. **XSS** — output escaping in templates
7. **Insecure Deserialization** — `unserialize()` on user input
8. **Using Components with Known Vulnerabilities** — `composer audit`
9. **Insufficient Logging** — security events not logged
10. **SSRF** — user-controlled URLs in HTTP requests

## 3. PHP Vulnerability Checklist

### Injection

- [ ] All SQL queries use prepared statements or parameterised queries
- [ ] No use of `$_GET`, `$_POST`, `$_REQUEST` directly in queries
- [ ] ORM queries use bound parameters (no raw string interpolation)
- [ ] Shell commands use `escapeshellarg()` / `escapeshellcmd()`
- [ ] LDAP queries use `ldap_escape()`
- [ ] XML input uses `libxml_disable_entity_loader(true)`

### Cross-Site Scripting (XSS)

- [ ] All output in templates escaped: `htmlspecialchars()` or template engine equivalent
- [ ] Content Security Policy headers set
- [ ] `X-XSS-Protection` header present
- [ ] DOM manipulation does not use `innerHTML` with user data

### Cross-Site Request Forgery (CSRF)

- [ ] All state-changing endpoints (POST/PUT/PATCH/DELETE) have CSRF tokens
- [ ] CSRF token validated on server side, not just client side
- [ ] `SameSite=Strict` or `SameSite=Lax` on session cookies

### Authentication and Session

- [ ] Passwords hashed with `password_hash()` (bcrypt/argon2), not MD5/SHA1
- [ ] Session ID regenerated after login (`session_regenerate_id(true)`)
- [ ] Session timeout configured
- [ ] Secure + HttpOnly + SameSite flags on session cookies
- [ ] Login attempts rate-limited
- [ ] Password reset tokens single-use, time-limited, invalidated on use

### Authorisation

- [ ] Every endpoint checks authorisation — not just authentication
- [ ] Vertical privilege escalation: can regular user access admin functions?
- [ ] Horizontal privilege escalation: can user A access user B data?
- [ ] Direct object references use indirect references or authorisation checks

### File Handling

- [ ] Uploaded files validated by content type, not just extension
- [ ] Upload directory outside webroot or has no execute permissions
- [ ] Filenames sanitised before storage
- [ ] Path traversal: `../` sequences removed from file paths

### Dependency Security

- [ ] `composer audit` run — no known CVEs in dependencies
- [ ] Outdated packages with security patches noted
- [ ] No abandoned packages in production dependencies

### Configuration

- [ ] `display_errors = Off` in production
- [ ] `expose_php = Off`
- [ ] Debug/development tools disabled in production
- [ ] Environment variables used for secrets, not config files

### Headers

- [ ] `Strict-Transport-Security` (HSTS) configured
- [ ] `X-Frame-Options: DENY` or `SAMEORIGIN`
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `Referrer-Policy` configured
- [ ] `Permissions-Policy` configured

## 4. Quick Scan Commands (Safe, Read-Only)

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

## 5. Authentication and Authorisation Deep-Dive

When reviewing auth systems:

1. **Map full auth flow** — where does user prove identity?
2. **Map full authz flow** — where does system check permissions?
3. **Test escalation paths** — what happens if you skip step?
4. **Check token lifecycle** — created, validated, refreshed, invalidated
5. **Check multi-tenancy** — any path where tenant A can reach tenant B?

## 6. Severity Classification

- **CRITICAL** — Direct exploitation, no authentication required, RCE/SQLi/auth bypass
- **HIGH** — Exploitation requires some access or conditions, data breach risk
- **MEDIUM** — Requires specific conditions, limited impact individually
- **LOW** — Defence in depth, information disclosure, best practice violation
- **INFO** — Observation, no direct risk

## 7. Vulnerability Finding Format

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

## 8. Reporting Rules

- Never report finding without evidence (code location, line number)
- Always include specific remediation — not just "fix SQL injection" but code example
- Group related findings — do not report 20 instances of same XSS pattern separately
- Always distinguish between confirmed vulnerability and potential risk
- Include positive findings: what codebase does well

## 9. Audit Summary Format

End every review with:

1. **Total findings by severity** — table showing count per severity level
2. **Top 3 most critical items** — three findings needing immediate attention
3. **Quick wins** — easy fixes with high security impact
4. **Systemic issues** — patterns needing architectural change, not just point fixes
5. **Positive findings** — what codebase does well from security perspective
