---
date: 2026-04-24
keywords: ["k8s"]
---

## M-FLOW-006: DNS switch validation — test before, batch after

Production DNS switch for 25 hostnames across two zone groups (wildcard *.services.get-e.com + 16 individual get-e.com records).
Test each hostname with `curl --connect-to` before switching DNS. Filter Route53 records by the old NLB hostname to find exactly which records to update. Switch all at once after validation passes. Keep a skip-list for broken services (e.g. cityjet-meals-api with unsynced routes) and handle separately.
