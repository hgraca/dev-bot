---
date: 2026-04-17
keywords: ["docker", "compose"]
---

## M-ARCH-015: Optional service architecture via Docker Compose profiles

Adding Langfuse and Graphiti as optional infrastructure services
Docker Compose profiles + .env boolean flags provide clean optional service architecture. Services are defined but only started when profile is active. Integrates well with existing Makefile patterns.
