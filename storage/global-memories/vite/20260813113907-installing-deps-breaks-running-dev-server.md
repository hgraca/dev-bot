---
date: 2026-08-13
keywords: ['vite', 'pnpm', 'dev-server', 'react-refresh']
---

## Installing a dependency while the Vite dev server is running breaks HMR

Running `pnpm add <dep>` while `vite` (dev server) is running corrupts its dependency optimizer, and subsequent page loads fail with a 500 on `@react-refresh` — the page renders blank. The Vite process stays alive but keeps returning 500 until it is restarted. Workaround: kill the running Vite process and start a fresh `pnpm run dev` after adding/removing any package. (In a Docker-based dev setup this means restarting the container's dev process — `make dev`.)
