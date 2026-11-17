---
date: 2026-11-15
keywords: ["forgejo", "oauth2", "consent", "backchannel", "single logout"]
---

## Forgejo re-asks OAuth consent on every login unless the client is confidential

`routers/web/auth/oauth.go` (`AuthorizeOAuth`) reuses a stored grant only when `app.ConfidentialClient && grant != nil`; for a public client it shows the consent page every time, per RFC 6749 §10.2, and there is no instance setting or `skip_secondary_authorization` in the API to change it. So a browser-side application (Decap CMS, SPA) that registers a public OAuth app costs a click on every login. Conversely, adding rows to `oauth2_grant` pre-authorises for a confidential client — that is what removes even the first prompt. For logout: the binary has no OIDC front- or back-channel endpoint, and `/user/logout` is a CSRF-protected POST, so no external page can end a Forgejo session; only `[session] SESSION_LIFE_TIME` or a person does. Upstream work is PR #15150 (scaffold only) with issues #13893, #15077, #1285.
