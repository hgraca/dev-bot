---
date: 2026-10-13
keywords: ["github", "pat", "fine-grained-token", "org-repos", "permissions"]
trigger-on: ["github-fine-grained-pat", "workflow-reads-org-repos"]
---

## Fine-grained PAT permissions for enumerating an org's repos and reading their files

GitHub's "Permissions required for fine-grained personal access tokens" maps `GET /orgs/{org}/repos` to repository **Metadata: read** and `GET /repos/{owner}/{repo}/contents/{path}` to **Contents: read**, so a token whose workflow lists an org's repositories and reads a file from each needs exactly those two read-only permissions with repository access set to **All repositories** — the "all" scope is what makes a newly created repo discovered automatically, with no token edit. No organisation-level permission is involved. Two footguns: the token's _resource owner_ must be the organisation (not the personal account), and a **classic** token never returns the `X-Accepted-GitHub-Permissions` header — that header appears only for fine-grained tokens, so probing it with a classic token silently yields nothing and the endpoint→permission mapping has to come from the docs.
