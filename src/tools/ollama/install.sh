#!/usr/bin/env bash
# Install ollama — runs inside a Docker container, no host binary needed.
# Ensures the ollama/ollama Docker image is pulled and available locally.
# Detects GPU availability (NVIDIA, AMD, Intel) and prepares GPU passthrough
# for Docker Compose using generic GPU capabilities.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# GPU detection helpers (_has_gpu, _gpu_vendor, _has_docker_gpu) live in
# src/_shared/functions.sh, sourced above — shared with qmd's native GPU
# selection (audit-25 F5: gpu_enabled must not conflate container passthrough
# with host GPU capability).

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  _info "ollama"

  # Pre-create the qmd models cache dir so the docker-compose bind mount
  # (${QMD_MODELS_DIR:-~/.cache/qmd/models} → /root/.qmd-cache) never has
  # docker create it as root. The qmd→ollama model share reads from it.
  mkdir -p "${QMD_MODELS_DIR:-$HOME/.cache/qmd/models}" 2>/dev/null || true

  # Inside a container there is no docker daemon to run ollama with — skip
  # cleanly instead of failing the pull. The host's ollama serves the API.
  # BUT record the machine's GPU state FIRST: gpu_enabled is consumed by other
  # modules too (qmd's QMD_LLAMA_GPU), whose local processes can use the GPU
  # directly even though no ollama container runs here (e.g. --gpus all
  # passthrough in the devbot-test container). Previously the early return
  # left gpu_enabled at the dist default false → qmd ran CPU-only on
  # GPU-capable machines.
  if ! docker info >/dev/null 2>&1; then
    if _has_gpu; then
      _info "GPU detected on this machine — recording gpu_enabled=true (qmd etc. can use it locally); ollama container skipped (no docker daemon)"
      _devbot_set_bool "gpu_enabled" "true"
    else
      _info "No GPU detected — recording gpu_enabled=false"
      _devbot_set_bool "gpu_enabled" "false"
    fi
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

  # ── 2. Detect GPU and configure passthrough ──────────────────────────────
  if _has_docker_gpu; then
    local vendor
    vendor="$(_gpu_vendor)"
    _info "$(printf '%s' "${vendor}" | tr '[:lower:]' '[:upper:]') GPU detected — enabling GPU passthrough for ollama."
    _devbot_set_bool "gpu_enabled" "true"
  else
    if _has_gpu; then
      local vendor
      vendor="$(_gpu_vendor)"
      case "$(uname -s)" in
        Darwin)
          _info "Apple Silicon GPU detected but Docker Desktop does not support GPU passthrough."
          _info "Ollama will run on CPU inside Docker."
          ;;
        Linux)
          case "${vendor}" in
            nvidia)
              _info "NVIDIA GPU detected but NVIDIA Container Toolkit is not installed."
              _info "Install it from: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
              ;;
            amd)
              _info "AMD GPU detected but ROCm kernel driver (/dev/kfd) is not accessible."
              _info "Ensure the amdgpu kernel module is loaded and user has render group access."
              ;;
            intel)
              _info "Intel GPU detected but /dev/dri is not accessible from containers."
              _info "Ensure the user has video/render group membership."
              ;;
          esac
          _info "Ollama will run on CPU."
          ;;
      esac
    else
      _info "No GPU detected — ollama will run on CPU."
    fi
    _devbot_set_bool "gpu_enabled" "false"
  fi

  _ok "ollama ready"
}

main
