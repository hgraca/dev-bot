---
date: 2026-11-18
keywords: ["forgejo", "GITEA_CUSTOM", "custom", "assets", "templates"]
---

## Forgejo's custom root is GITEA_CUSTOM, not <workdir>/custom

The official Forgejo image exports `GITEA_CUSTOM=/data/gitea`, so customisation files go directly under that path: templates at `/data/gitea/templates/…` and public assets at `/data/gitea/public/assets/…`, the latter served at `/assets/…`. Docs and older Gitea advice say `custom/public`, which resolves to `${GITEA_CUSTOM}/public` — with the image default that is `/data/gitea/public`, not `/data/gitea/custom/public`; a file dropped in the latter 404s while the layer silently falls through to the built-in assets. Read the effective root from the running process (`tr '\0' '\n' < /proc/1/environ | grep GITEA_CUSTOM`) before mounting or copying, and set `GITEA_CUSTOM` explicitly in the Deployment so the mount paths and the application agree after an image bump.
