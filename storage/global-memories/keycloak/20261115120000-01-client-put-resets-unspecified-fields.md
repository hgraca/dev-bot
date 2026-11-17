---
date: 2026-11-15
keywords: ["keycloak", "client-secret", "invalid client secret", "confidential client"]
---

## Updating a Keycloak client with PUT resets every field you leave out

`PUT /admin/realms/{realm}/clients/{id}` replaces the client representation: omit `confidential_client` and the client silently becomes public (an OAuth consent page starts appearing again), omit `client_secret` and Keycloak regenerates it, so every token exchange afterwards fails with `unauthorized_client: invalid client secret` while the cluster still holds the old value. The API never returns the secret on read, so the mismatch is invisible until exchanges break. Read the client, change only the field you mean to, send the whole object back including the stored secret — and verify by posting a deliberately bad code to the token endpoint: `invalid client secret` means drifted, anything about the code means the secret matches. When a client has drifted, deleting and recreating it is usually cheaper than reasoning about what the last PUT lost.
