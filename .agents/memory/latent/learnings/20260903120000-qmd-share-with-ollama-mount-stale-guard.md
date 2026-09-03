---
date: 2026-09-03
keywords: ["qmd", "share-with-ollama", "ollama", "qmd-cache", "stale-mount"]
---

# qmd share-with-ollama.sh: mechanism, stale-mount failure, and guard

`src/agentic/qmd/tools/share-with-ollama.sh` shares qmd's downloaded GGUFs (`~/.cache/qmd/models`, mounted read-only into `dev-bot-ollama` as `/root/.qmd-cache` via `src/tools/ollama/docker-compose.yml`) with ollama under a cosmetic `qmd/<name>:<quant>` namespace — qmd itself never talks to ollama (it runs its own llama.cpp on `hf:` URIs). Import is `ollama create` from a temp Modelfile `FROM /root/.qmd-cache/<gguf>` (line ~112), then the materialized blob in `/root/.ollama/models/blobs/` is swapped for a symlink to the GGUF (line ~117): zero download, zero duplicate bytes, and `ollama rm` only removes the manifest+symlink. Idempotent via `ollama list | grep ^qmd/<name>:<quant>$`. Three models: embeddinggemma-300m (q8_0), qmd-query-expansion-1.7b (q4_k_m), qwen3-reranker-0.6b (q8_0).

Failure mode fixed 2026-09-03: if the host cache dir is replaced while the container runs, docker keeps the bind pinned to the orphaned empty dir → `ollama create` 400s with the misleading "invalid model name" (FROM path unreadable → server name-parses it) on every `devbot up`. `--no-recreate` in bin/up.sh and a `test -d`-only guard hid it. The guard (`_ensure_qmd_cache_mount`) now: detects staleness via `_mount_is_stale()` (each host-downloaded GGUF must be `test -f`-visible inside the container), recreates through a shared `_recreate_ollama_container()` that uses `--force-recreate` (plain `up -d` is a no-op when the compose spec matches), waits for `ollama list` to respond (`_wait_for_ollama`, 15×1s), and errors loudly if the mount still won't heal. Covered by `src/agentic/qmd/tests/share_with_ollama_tests.bats` (7 tests, stub-docker-in-PATH style).

Gotcha for future sessions: a healthy-looking `ollama list` that already contains `qmd/*` models means an earlier container incarnation imported them — check blob symlinks (`ls -la storage/ollama/models/blobs/`) and manifest mtimes before assuming the share never worked.
