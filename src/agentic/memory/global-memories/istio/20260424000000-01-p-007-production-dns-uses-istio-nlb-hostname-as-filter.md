---
date: 2026-04-24
keywords: ["istio"]
---

## P-007: Production DNS uses Istio NLB hostname as filter key

- **Pattern**: In Route53, filter records by the old NLB hostname (e.g. `a9d8c9f98009c43e498624dd1252acc4`) to find all A alias records that need updating. Two groups: wildcard `*.services.get-e.com` (covers 9 hostnames) and individual `get-e.com` subdomains (16 records including multi-level like `api.hotels.get-e.com`).
- **When**: DNS switch tasks in production.
