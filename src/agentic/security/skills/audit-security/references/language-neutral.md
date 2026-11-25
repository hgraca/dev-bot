# Language-neutral checklist

Work this before any language checklist. These checks hold regardless of stack, so they are what a
review has when the project is not PHP — and the language sections then add only what reading that
language can see.

Each row is falsifiable: it states something to look for in the code, not a practice to admire.

### A01 — Broken Access Control

- [ ] Every handler that returns an object checks the caller's right to **that object**, not merely
      that the caller is authenticated
- [ ] An identifier supplied in a request is never itself the access decision
- [ ] A server-side request to a user-supplied URL is allowlisted by host, not blocklisted

### A02 — Security Misconfiguration

- [ ] Debug and verbose error modes are off in the artefact that deploys, not only in the repository's
      default configuration
- [ ] No default or shared credential ships with a deployment
- [ ] Cross-origin access names explicit origins wherever credentials are allowed

### A03 — Software Supply Chain

- [ ] A lockfile is committed and the build installs from it
- [ ] Direct dependencies are pinned; a range that resolves differently per install is a gap
- [ ] The integrity of a downloaded artefact is verifiable — checksum, signature or provenance

### A04 — Cryptographic Failures

- [ ] No ECB mode, and no static or reused IV or nonce
- [ ] Security-relevant randomness comes from a CSPRNG, never a general-purpose PRNG
- [ ] TLS verification is never disabled in client configuration

### A05 — Injection

- [ ] Untrusted input reaches an interpreter only as a bound parameter, never as concatenated text
- [ ] Output encoding is applied at the sink, not at the source
- [ ] A path built from input is canonicalised and constrained to a base directory

### A06 — Insecure Design

- [ ] A threat model exists, and the code reflects its trust boundaries
- [ ] Business limits — quantity, frequency, total — are enforced server-side
- [ ] No security decision is delegated to the client

### A07 — Authentication Failures

- [ ] Passwords are stored with a memory-hard KDF, never a fast hash
- [ ] A session is invalidated on logout, on password change and on privilege change
- [ ] Credential-bearing endpoints are rate-limited per identity, not per IP alone

### A08 — Software or Data Integrity

- [ ] No untrusted serialised payload is deserialised without an explicit type allow-list
- [ ] A signed or encrypted payload is verified before it is used
- [ ] CI configuration cannot be changed by an unreviewed pull request from a fork

### A09 — Security Logging and Alerting

- [ ] Authentication, authorisation and privilege changes are logged with actor, action, object and
      outcome
- [ ] No credential, token or personal data reaches a log
- [ ] Something alerts on the events that matter — a log nobody reads is not monitoring

### A10 — Mishandling of Exceptional Conditions

- [ ] A failure inside an authorisation path denies by default
- [ ] User-facing errors expose no stack trace, file path or internal identifier
- [ ] Every external call has a timeout, and its failure path is stated

## Using it

Record each category in the coverage table as `checked`, `clean`, `not applicable` (with the reason)
or `not examined` (with the reason). On a stack with a language section here, run that section after
this one; on a stack without, these are the checks the report can claim.
