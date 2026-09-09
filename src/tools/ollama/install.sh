#!/usr/bin/env bash
# Install ollama — runs inside a Docker container, no host binary needed.
# Ensures the ollama/ollama Docker image is pulled and available locally.
#
# GPU detection no longer lives here: _devbot_detect_gpu (src/_shared/
# functions.sh) records gpu_enabled from bin/install.sh / bin/update.sh, so
# the result survives the ollama module being disabled in the `modules` map
# (it is off by default; consumer compose fragments boot it on demand). If
# this module's install runs at all (module enabled), docker compose pulls
# the image on first `up` regardless — the explicit pull here just warms it.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  _info "ollama"

  # Pre-create the qmd models cache dir so the docker-compose bind mount
  # (${QMD_MODELS_DIR:-~/.cache/qmd/models} → /root/.qmd-cache) never has
  # docker create it as root. The qmd→ollama model share reads from it.
  mkdir -p "${QMD_MODELS_DIR:-$HOME/.cache/qmd/models}" 2>/dev/null || true

  # Inside a container there is no docker daemon to run ollama with — skip
  # cleanly instead of failing the pull. The host's ollama serves the API.
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — ollama not installed here; the host serves the ollama API instead"
    return 0
  fi

  # ── 1. Pull the Docker image ─────────────────────────────────────────────
  if docker image inspect ollama/ollama:latest >/dev/null 2>&1; then
    _skip "ollama/ollama:latest image already pulled"
  else
    _info "Pulling ollama/ollama:latest Docker image..."
    docker pull ollama/ollama:latest
    _ok "ollama/ollama:latest image pulled"
  fi

  _ok "ollama ready"
}

main
