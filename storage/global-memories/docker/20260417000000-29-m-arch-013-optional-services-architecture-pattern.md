---
date: 2026-04-17
keywords: ["docker", "compose"]
---

## M-ARCH-013: Optional services architecture pattern

Adding Langfuse and Graphiti as optional Docker services
Use Docker Compose profiles with env flags. Create env.is_enabled helper, add SERVICENAME_ENABLED vars to .env.dist, define services under profiles in compose.yml, make Makefile profile-aware
