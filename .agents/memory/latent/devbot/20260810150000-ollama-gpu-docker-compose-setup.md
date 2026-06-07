---
date: 2026-08-10
keywords: ["devbot", "ollama", "docker", "gpu"]
trigger-on: ["ollama-gpu-setup"]
---

# Ollama Docker Container Needs Explicit GPU Compose File

The ollama Docker container has no GPU access unless `docker-compose.gpu.yml` is included in the `docker compose up` command. Even when `gpu_enabled: true` in `.devbot.global.jsonc` and a `docker-compose.gpu.yml` exists at the project root, the container won't get GPU if started manually from `src/tools/ollama/` instead of via `bin/up.sh` (which auto-appends the GPU file). Verify with `docker inspect <container> --format '{{json .HostConfig.DeviceRequests}}'` — should show `[{"Capabilities":[["gpu"]]}]`. If `null`, the container has no GPU.
