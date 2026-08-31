---
date: 2026-06-14
keywords: ["svelte", "project-structure", "modules", "ports-adapters"]
---

## Per-module structure bundles entity, port, service, and adapters together

Instead of layer-separated directories (src/domain/, src/ports/, src/adapters/, src/services/), each feature lives in its own module at src/modules/User/: User.ts (entity), UserRepository.ts (port interface), UserService.ts (orchestration), and adapters/db/, adapters/api/ (implementations). Page components at src/pages/ import services with relative paths. SvelteKit routes at src/routes/ stay thin — they import services from modules, not raw adapters. This makes each module self-contained and swapable.
