---
date: 2026-11-02
keywords: ["github-actions", "app-token", "404", "create-github-app-token"]
aliases: ["repository not found", "installation token propagation", "git ls-remote 404"]
trigger-on: ["github-app-token-fetch"]
---

## A freshly minted installation token can answer 404 for a moment

A job that mints an app installation token with `actions/create-github-app-token` and uses it a
second later can get `remote: Repository not found.` (HTTP 404) from a repository the app can
read. The token is valid and the grant exists — a replica has not caught up yet. Observed once in
a nightly export: the same workflow at the same commit succeeded the day before and the two nights
after, and seven sibling repositories using the same app and the same source repository succeeded
within a minute of the failure.

Treat that 404 as retryable, not as a permission error: wrap the git network calls (`ls-remote`,
`fetch`) in a bounded retry — three attempts, 30s apart — and only then emit `FATAL`. A single-shot
`git ls-remote` exits 128 and fails the whole job. Do not "fix" it by widening the token's
permissions, and do not assume a 404 means the app lost access.
