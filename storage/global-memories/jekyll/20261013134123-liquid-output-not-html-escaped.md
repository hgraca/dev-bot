---
date: 2026-10-13
keywords: ["jekyll", "liquid", "escape", "html-injection", "xss"]
trigger-on: ["jekyll-renders-external-data", "liquid-untrusted-values"]
---

## Liquid `{{ }}` does not HTML-escape — escape any value that came from outside the site

Jekyll/Liquid emits `{{ value }}` verbatim; there is no auto-escaping, so any value originating outside the site — a `_data/*.json` file, a fetched API payload, a front-matter field an attacker can write — is injected as raw HTML/JS into the rendered page. A single `"description": "</span><script>…</script>"` in a data-driven page executes on the site origin, and on a shared GitHub Pages origin (`<org>.github.io`) that reaches every sibling project site too. Fix at output by applying the `escape` filter to **every** interpolated field (`{{ p.name | escape }}`, `{{ p.description | escape }}`, and attribute positions like `href="{{ p.docs_url | escape }}"`), and belt-and-braces at input by storing a normalised URL (`new URL(v).href`, which percent-encodes `"`, `<`, `>` and spaces) instead of the raw string once it validates. Verifying a value is an `http(s)` URL does not make it safe to interpolate — validation and output-encoding are separate controls, and fixing only `description` leaves `name`, `category` and `docs_url` exploitable.
