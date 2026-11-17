---
date: 2026-11-15
keywords: ["decap", "decap-cms", "oauth", "localstorage", "session"]
---

## Decap CMS restores its session from localStorage before it ever authenticates

Decap reads `localStorage['decap-cms-user']` (JSON with at least `token`, and usually `backendName`) at start-up and, when it finds one, goes straight into the CMS without calling the backend `authenticate()`. That is the seam to use when you need to sign a user in with your own flow: write that key before `decap-cms.js` initialises and the built-in Forgejo/Gitea backend never runs its OAuth redirect. Practical constraints: the write must happen in an inline script placed before the CDN `<script>` (Decap initialises on DOMContentLoaded); a backend registered with `CMS.registerBackend(name, class)` needs no base class and no npm package, because the registry stores `{ init: (...args) => new cls(...args) }` and the published UMD of `decap-cms-backend-gitea` is an empty stub; and the admin page itself cannot carry a client secret, so the credential has to be minted server-side and delivered to the page.
