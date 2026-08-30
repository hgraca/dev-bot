#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/functions.sh
# Shared helpers for codebase-index module scripts (install.sh, update.sh, init.sh).
# Source this file, then call the functions.
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Ollama models required by codebase-index.
# Shared between install.sh and update.sh.
LOCAL_MODELS=(
  "nomic-embed-text:latest"
)
