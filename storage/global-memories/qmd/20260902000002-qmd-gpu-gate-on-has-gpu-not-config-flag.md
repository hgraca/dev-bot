---
date: 2026-09-02
keywords: ["qmd", "gpu_enabled", "docker", "passthrough", "config"]
trigger-on: ["qmd-gpu-decouple", "gpu_enabled"]
---

## gpu_enabled config flag conflates docker passthrough with native host GPU — qmd must gate on _has_gpu

`gpu_enabled` (set by `src/tools/ollama/install.sh` GPU detection) is a single
global flag consumed by BOTH (a) up.sh/down.sh deciding whether to append
docker-compose.gpu.yml (GPU passthrough for the ollama _container_), and (b)
qmd's `QMD_LLAMA_GPU` selection. On Docker-Desktop-on-macOS the container
cannot get passthrough (`_has_docker_gpu` false) so install.sh set
`gpu_enabled=false` — which wrongly forced qmd CPU-only even though qmd runs as
a plain local process and the Apple Silicon Metal GPU was usable. Fix: qmd's
selection (`_qmd_gpu_value()` in src/_shared/functions.sh) must gate on the
native host probe `_has_gpu()`, NOT on the `gpu_enabled` config flag. The GPU
probes (_has_gpu/_gpu_vendor/_has_docker_gpu) live in _shared so both consumers
share one implementation. Beware: the audit's naive one-liner fix (flip
gpu_enabled=true on _has_gpu) breaks `devbot up` on Docker Desktop — the flag
still gates the compose GPU override.
