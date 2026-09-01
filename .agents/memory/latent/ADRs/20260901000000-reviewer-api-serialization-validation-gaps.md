---
date: 2026-09-01
keywords: ["reviewer", "review-implementation", "api-serialization", "validation", "improve-reviewing"]
---

## Reviewer skill extended with API-serialization, validation-bound, and constraint-mapping checks

After an external (GitHub Copilot) review caught issues our reviewer missed on the SAML SSO changeset, the reviewer inspection skill gained three Laravel issue types: (1) **API resource serialization must be scalar** — backed enums silently `json_encode` to `{}`, so resources must use `->value`/`->getValue()` and response tests must assert the serialized value; (2) **validation bounded to DB schema** — every validated string needs a `max` rule matching its column length so oversized input fails 4xx instead of leaking a 500; (3) **DB constraint-violation → field mapping** — a 1062 handler must parse the violated key name and map to the correct field rather than hardcoding one. The reviewer agent also gained a behavioural MUST: proposed fixes must cover every variant/path of the issue (all error keys, branches, call sites), not just the reported case — the previously proposed 1062→400 fix was incomplete because it mislabelled the field for other unique keys. Rationale: these are all silent-failure classes (wrong-but-working output, 500s from schema/validation drift, misleading error fields) that inspection-level checks now catch before an external review does.
