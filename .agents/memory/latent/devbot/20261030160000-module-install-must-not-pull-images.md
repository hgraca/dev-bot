---
date: 2026-10-30
keywords: ["devbot", "install", "docker", "mcp", "module"]
trigger-on: ["module-install-image-pull"]
---

# Module install.sh Must Not Pull Docker Images

`bin/install.sh` runs every module's `install.sh` machine-wide, so `bin/tests/install_no_image_pull_tests.bats` fails any `install.sh` whose text contains `docker pull` — comments included. A module whose MCP server is a container must pull lazily at launch instead: use `docker run ... --pull=missing` in the launcher and keep `install.sh` to a docker-presence check. `update.sh` may verify a candidate tag with `docker manifest inspect` (metadata only, no layers) before rewriting a pin, but must not pull either. The guard's own text notes the ollama image alone is 4.8 GB, which is the reason.
