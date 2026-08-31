---
date: 2026-04-23
keywords: ["k8s"]
---

## P-006: Staging DNS uses wildcard A alias records

- **Pattern**: The `get-e.dev` Route53 zone uses wildcard A alias records (`*.get-e.dev`, `*.hotels.get-e.dev`, `*.portal.get-e.dev`, `*.api.get-e.dev`) pointing to the ingress LB. To switch traffic, update these 4 wildcards (skip `*.disruption.get-e.dev`). Some hostnames (`*.services.get-e.dev`, `*.staging.get-e.dev`, positioning subdomains) don't have DNS records — accessed via other means.
- **When**: DNS switch tasks (Task 9, Task 18).
