---
date: 2026-09-26
keywords: ["mcp", "mcp-proxy-for-aws", "authentication", "sigv4"]
trigger-on: ["mcp-proxy-skip-auth"]
---

## `mcp-proxy-for-aws --skip-auth` does not disable signing

`--skip-auth` changes only what happens when credentials **cannot be resolved**: the request is sent unsigned instead of raising. With credentials available the proxy signs exactly as it would without the flag. Its documented purpose is an endpoint that needs no SigV4, so passing it against an endpoint that *does* — the managed `https://aws-mcp.us-east-1.api.aws/mcp` — is at best a no-op and at worst a silent downgrade to unsigned requests if the credentials ever disappear. It also interacts with pinning: because signing (and therefore `--profile` resolution) happens only when credentials are being resolved, keep `--skip-auth` out of any launcher that means to pin an identity.
