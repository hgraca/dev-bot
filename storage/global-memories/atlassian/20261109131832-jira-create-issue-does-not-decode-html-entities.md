---
date: 2026-11-09
keywords: ["atlassian", "createJiraIssue", "html entities", "summary", "escaping"]
---

## Never HTML-escape a string passed to `createJiraIssue`

Writing `"summary": "Identity &amp; SSO (SAML)"` stores the literal text `Identity &amp; SSO (SAML)` — the value is not decoded on the way in, so the issue renders with the entity visible. Pass `&` raw; JSON encoding already handles it. The same applies to `<`, `>` and quotes in summaries, descriptions and comments: the MCP converts markdown to ADF and does not unescape HTML entities. Recover a mistake with `editJiraIssue` and the plain characters (`{"summary": "Identity & SSO (SAML)"}`), which is idempotent and safe.
