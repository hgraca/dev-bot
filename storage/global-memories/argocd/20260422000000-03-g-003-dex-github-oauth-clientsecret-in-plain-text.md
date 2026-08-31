---
date: 2026-04-22
keywords: ["argocd"]
---

## G-003: Dex GitHub OAuth clientSecret in plain text

- **Problem**: The `argocd-cm` ConfigMap contains the Dex GitHub OAuth `clientSecret` in plain text within the `dex.config` YAML string.
  Rotate the secret and move it to an `argocd-secret` reference using `$dex.github.clientSecret`.
