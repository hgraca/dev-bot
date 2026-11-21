---
date: 2026-11-18
keywords: ["playwright", "cookies", "addCookies", "domain", "subdomain"]
---

## Playwright addCookies without a leading dot is host-only

`context.addCookies([{ name, value, domain: 'example.test', path: '/' }])` creates a cookie the subdomain's `document.cookie` cannot see: the page that reads it on `app.example.test` silently falls back to defaults while `context.cookies()` still lists the cookie, so the failure looks like the application ignoring its own script. Prefix the domain with a dot (`.example.test`) to get the shared parent-domain cookie a real site writes; the jar then reports `domain: '.example.test'` and the subdomain sees it. Recognise the symptom as harness-side, not app-side: the attribute the app derives from the cookie never appears, but the cookie is present in the context.
