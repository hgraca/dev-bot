---
date: 2026-06-17
keywords: ["shell", "curl", "jq", "redirect", "https"]
---

## curl -sf without -L doesn't follow redirects — returns HTML body not JSON

When `curl -sf` hits an HTTP endpoint that redirects (301/302) to HTTPS, it does NOT follow the redirect and instead returns the first response body (typically HTML page like `301 Moved Permanently`). If piping to `jq`, this causes "parse error: Invalid numeric literal". Fix: either add `-L` flag to follow redirects, or use the HTTPS URL directly to avoid the redirect. `-f` treats only 4xx/5xx as errors — 3xx passes through silently.
