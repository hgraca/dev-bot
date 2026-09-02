---
date: 2026-09-02
keywords: ["test-project", "harness", "test-oc", "test-cc", "devbot"]
see: ["PDRs/20260902204416-macos-flag-rejected-dockurr-macos.md"]
---

# oc/cc harness tests: where they live and how they run

The two harness tests for devbot live inside the dev-bot repo at `tests/test-project/` (a PokeAPI PHP kata scaffold registered as a project in `.devbot.global.jsonc`), NOT in a sibling repo. Both were added in commit `e8dda74a` ("Add test project") — now merged to `main`.

Layout and flow:

- `test-oc.sh` / `test-cc.sh` — host launchers. They `docker run` the `devbot-test` image (`FROM ubuntu`, built via `make build-test-image`) with the project bind-mounted at `/app`, host uid, `--network host` (routes to host ollama at `localhost:18434`, which the launcher requires up front), GPU pass-through when present, and host cache mounts (`~/.cache/qmd`, `opencode`, `bun`, `~/.npm`).
- `test-oc-inner.sh` / `test-cc-inner.sh` — run inside the container: set harness in `.devbot.project.jsonc` (oc: `opencode`; cc: `claudecode`), apt-install prereqs, create a throwaway git repo in `/app` (removed via EXIT trap so the host mount stays clean), then source `test-reinit.sh`, and finally drop into an interactive shell (`bash -i`). **Gotcha: the oc inner script's actual `opencode run` audit step is currently commented out**; only cc runs the real audit (`devbot -p "/devbot:audit"`).
- `test-reinit.sh` — shared, sourced by both inner scripts: installs devbot from `hgraca/dev-bot@<branch>` (via `DEV_BOT_TEST_BRANCH`, default `main`) if missing, `rm -rf`s scaffolded artifacts, runs `devbot reinit`, grants external-dir permissions, pre-seeds the opencode-codebase-index plugin cache (pinned `0.25.1`), and does a non-fatal `qmd pull` guard.

Conventions: launchers take **one positional `<branch>` arg** (`BRANCH="${1:-main}"`) — there is NO flag parsing anywhere; all other inputs arrive as env vars (`DEV_BOT_TEST_BRANCH`, `SKIP_CONFIRM`, `INDEX_PATH`, `QMD_EMBED_TIMEOUT`, `JETBRAINS_PROJECT_PATH`). The test qmd index is isolated per-run via `INDEX_PATH=/tmp/qmd-test/index.sqlite` so host index is never polluted.

Operational notes: containers use a fixed name (`devbot-test-oc` / `devbot-test-cc`) with EXIT/INT/TERM trap force-removal. A live container owns the fixture tree state (leftover nested `.git`, `.agents/`, harness in `.devbot.project.jsonc`) while running — do not mutate `tests/test-project` or kill the container while a run is in progress.

The Dockerfile bakes opencode + claude CLI + qmd + CUDA libs, so runs never reinstall harness CLIs; only devbot itself is reinstalled per branch.
