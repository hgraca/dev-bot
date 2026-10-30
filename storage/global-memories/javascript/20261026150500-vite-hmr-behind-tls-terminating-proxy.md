---
date: 2026-10-26
keywords: ["vite", "hmr", "traefik", "tls", "mkcert"]
aliases: ["hmr.clientPort", "wss", "vite behind reverse proxy", "basicSsl"]
trigger-on: ["vite-dev-container", "traefik-host-routing"]
---

## Vite HMR behind a TLS-terminating proxy, without losing host-run TLS

Behind Traefik (or any TLS-terminating proxy on 443) Vite advertises the container's internal port for its HMR socket, so the browser never connects and edits silently never reach the page — set `server.hmr.clientPort = 443` (protocol follows the page). Gate it on a variable only the container sets (`VITE_ALLOWED_HOST`, set by compose), because a direct `pnpm start` on the host has no 443 to dial. The same variable is the right switch for the TLS plugins: enable `vite-plugin-mkcert`/`basicSsl` only when it is unset, so the host run keeps HTTPS and the container run leaves TLS to the proxy instead of generating a certificate nobody serves.
