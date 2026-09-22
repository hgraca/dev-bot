#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/functions.sh
# Shared helpers for the codebase-memory module's own scripts (up.sh, and the
# session-start index hook's tooling). Source this file, then call the
# functions.
#
# NOTE: unlike codebase-index, this module needs NO Ollama model pulls —
# codebase-memory-mcp bundles its nomic embeddings inside the native binary.
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
