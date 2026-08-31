---
date: 2026-08-20
keywords: ['docker', 'prisma', 'alpine', 'openssl', 'node']
trigger-on: ['prisma-alpine-openssl', 'prisma-node-alpine-engine']
---

## Prisma 6 on node:22-alpine needs no extra openssl

Prisma 6's query engine on Alpine resolves to the `linux-musl-openssl-3.0.x` target and links against OpenSSL 3's `libssl.so.3`. The `node:22-alpine` image (Alpine 3.24) already ships `libssl.so.3`/`libcrypto.so.3` via its `libssl3`/`libcrypto3` base packages, so no `apk add openssl` (and no legacy `openssl1.1-compat`) is needed in the Dockerfile. The `openssl1.1-compat` advice only applies to the old `node:14-alpine` (OpenSSL 1.1, Alpine ≤3.16) + Prisma 3 stack. Verify with `docker run --rm node:22-alpine sh -c 'ls /usr/lib/libssl* /usr/lib/libcrypto*'` — if `libssl.so.3`/`libcrypto.so.3` are present, Prisma 6 needs nothing extra.
