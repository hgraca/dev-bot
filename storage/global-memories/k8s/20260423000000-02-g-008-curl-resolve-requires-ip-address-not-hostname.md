---
date: 2026-04-23
keywords: ["k8s"]
---

## G-008: curl --resolve requires IP address, not hostname

- **Problem**: `curl --resolve host:port:address` expects a numeric IP for `address`. Passing a hostname (e.g., NLB DNS name) silently fails — curl returns HTTP status `000` with no error message.
  Use `--connect-to "host:port:hostname:port"` instead, which accepts hostnames. Or resolve the hostname to IP first.
