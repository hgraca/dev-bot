#!/usr/bin/env bash
# Install ollama — runs inside a Docker container, no host binary needed.
# Ensures the ollama/ollama Docker image is pulled and available locally.
# Detects GPU availability (NVIDIA, AMD, Intel) and prepares GPU passthrough
# for Docker Compose using generic GPU capabilities.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── GPU detection ──────────────────────────────────────────────────────────────

# _has_gpu: returns 0 if any usable GPU is available on the host.
#   NVIDIA: nvidia-smi must exist and succeed.
#   AMD:    rocm-smi must exist and succeed, or lspci shows AMD GPU.
#   Intel:  /dev/dri/renderD* exists and a compatible GPU is detected.
#   macOS:  Apple Silicon (arm64) has built-in GPU.
_has_gpu() {
  case "$(uname -s)" in
    Darwin)
      [[ "$(uname -m)" == "arm64" ]]
      return $?
      ;;
    Linux)
      # NVIDIA
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        return 0
      fi
      # AMD ROCm
      if command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        return 0
      fi
      # Intel via /dev/dri (render nodes = GPU available)
      if ls /dev/dri/renderD* >/dev/null 2>&1; then
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# _gpu_vendor: prints the GPU vendor name for the primary GPU.
_gpu_vendor() {
  case "$(uname -s)" in
    Darwin)
      echo "apple-silicon"
      return 0
      ;;
    Linux)
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
        return 0
      fi
      if command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        echo "amd"
        return 0
      fi
      if ls /dev/dri/renderD* >/dev/null 2>&1; then
        # Check if it's Intel or AMD integrated via lspci
        if command -v lspci >/dev/null 2>&1; then
          if lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
            echo "intel"
            return 0
          fi
          if lspci 2>/dev/null | grep -qi "VGA.*AMD\|VGA.*Advanced Micro Devices"; then
            echo "amd"  # AMD integrated (not ROCm)
            return 0
          fi
        fi
        echo "intel"  # fallback — most common with /dev/dri/render
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# _has_docker_gpu: returns 0 if Docker GPU passthrough is available.
#   Linux (NVIDIA): nvidia-smi + NVIDIA Container Toolkit.
#   Linux (AMD):    rocm-smi + /dev/kfd accessible.
#   Linux (Intel):  /dev/dri/renderD* accessible.
#   macOS:          always 1 — Docker Desktop does not support GPU passthrough.
_has_docker_gpu() {
  [[ "$(uname -s)" != "Linux" ]] && return 1
  _has_gpu || return 1

  local vendor
  vendor="$(_gpu_vendor)"
  case "${vendor}" in
    nvidia)
      docker info 2>/dev/null | grep -qi nvidia \
        || [[ -x "/usr/bin/nvidia-container-toolkit" ]]
      return $?
      ;;
    amd)
      # AMD ROCm requires /dev/kfd for Docker passthrough
      ls /dev/kfd >/dev/null 2>&1
      return $?
      ;;
    intel)
      # Intel GPU in Docker requires /dev/dri and the intel-gpu-plugin
      ls /dev/dri/renderD* >/dev/null 2>&1
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

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
