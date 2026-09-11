---
date: 2026-09-11
keywords: ["e2e", "ollama", "codebase-index", "test-oc"]
---

# e2e launchers require host ollama only for the codebase-index engine

`tests/test-project/test-oc.sh` and `test-cc.sh` used to hard-require the host ollama at `http://localhost:18434` before starting their container (`curl /api/tags`), because the container runs `--network host` and reaches the host's `dev-bot-ollama`. That blocked every run whose engines need no ollama: **only `codebase-index` embeds via the host ollama**. `codebase-memory` bundles its nomic embeddings, `mdctx` is zero-ML, and `qmd` uses its own llama.cpp GGUF models (`qmd pull`) — the `:18434` reference appears in dev-bot source only under `codebase-index/` and `litellm/`.

With the shipped defaults now `codebase_index_provider: codebase-memory` + `memory_search_provider: mdctx`, and `bin/up.sh` starting docker services only for ENABLED modules (while `.devbot.global.jsonc` sets `ollama: false`), the guard's `devbot up` advice was a no-op — `devbot up` selects zero compose files. Fix (commit `e6119616`): the guard moves inside the container. `test-reinit.sh` (sourced by both inner scripts, after install, before reinit) calls `require_host_ollama_for_codebase_engine` from `tests/test-project/test-lib.sh`, which resolves the installed dev-bot's effective provider via `_devbot_get_codebase_provider` and fails only when it is `codebase-index` and `:18434` is unreachable. Covered by `bin/tests/e2e_ollama_gate_tests.bats`. To start ollama directly when a run genuinely needs it: `docker compose -f src/tools/ollama/docker-compose.yml -f docker-compose.gpu.yml up -d`.
