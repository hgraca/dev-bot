---
date: 2026-06-24
keywords: ["docker", "vite", "hmr", "ipv6"]
trigger-on: ["vite-docker-dev", "docker-vite-hmr", "vite-config-docker"]
---

## Vite inside Docker requires host 0.0.0.0 with localhost HMR

When running Vite dev server inside a Docker container, the default bind address causes asset URLs to be generated as `[::1]:5173` (IPv6 loopback) which the host browser cannot reach. Fix: add to vite.config.ts:

```ts
server: { host: '0.0.0.0', hmr: { host: 'localhost' } }
```

This makes Vite listen on all container interfaces while injecting `localhost:5173` URLs into the page — which the host can reach via the mapped port.
