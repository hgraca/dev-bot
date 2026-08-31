---
date: 2026-06-19
keywords: ["php", "composer", "github-actions", "auth"]
trigger-on: ["composer-auth-github-actions-app-token"]
---

## Composer must be explicitly configured to use the GitHub App token after `actions/create-github-app-token`

When switching private Composer repo auth from SSH deploy keys to `actions/create-github-app-token@v2`, generating the token alone is insufficient — Composer downloads dist archives from `api.github.com` via HTTPS, and without the token in its auth config, GitHub returns 404 (not 401/403 — it hides private repos from unauthenticated requests). After the token step (`id: app-token`), run `composer config --global github-oauth.github.com ${{ steps.app-token.outputs.token }}` to wire the token into Composer's global auth. The old SSH approach worked transparently because the SSH agent handled git operations automatically; GitHub App tokens require explicit wiring into each tool that needs them.
