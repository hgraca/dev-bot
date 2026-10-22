---
date: 2026-10-22
keywords: ["devbot", "install", "docker-image", "lazy-pull"]
aliases: ["install must stay image-free", "eager image pull", "canary at install"]
---

# `devbot install` must stay image-free

## The rule

`bin/install.sh` runs **every** module's `install.sh` with `--all` (machine-wide provisioning from
`87d5ab3f`, so a module enabled only in one project is still provisioned). Anything an install
script downloads is therefore paid on every machine, including modules disabled everywhere. Docker
images belong to the first `up` that needs them: `docker compose` pulls a missing image itself, and
`bin/up.sh` names each absent image before it starts (`_announce_missing_images`). A module whose
compose is generated outside `src/` must announce its own pull (the datasources module does, via
`_announce_missing_toolbox_image` in `up.sh`).

## The three leaks that broke the rule

- Explicit `docker pull` in the `ollama` (4.8 GB), `litellm` (1.2 GB) and `datasources` installers.
- The datasources validator canary: `install.sh` renders through `render.sh` →
  `validate_catalogue.py`, whose `docker run` pulls the toolbox image. Install now renders with
  `DATASOURCES_SKIP_CANARY=1` → `--skip-canary`; engines pass through unprobed (structural only) and
  first use validates them.
- `codebase-index/install.sh`'s model ensure: `_ensure_ollama_models_detached` falls back to
  `compose up -d ollama` when the API is down, pulling the ollama image. Removed from install —
  `codebase-index/up.sh` already pulls `nomic-embed-text` on every boot.

## Guards

`bin/tests/install_no_image_pull_tests.bats` fails on a `docker pull` in any `install.sh` and on any
install-time use of the ollama model-ensure helper. The mirror rule holds at boot: every docker probe
on the `up` path is bounded and daemon-gated (see the `docker` global-memory note).
