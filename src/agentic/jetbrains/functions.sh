#!/usr/bin/env bash
# =============================================================================
# src/agentic/jetbrains/functions.sh
# Shared helpers for jetbrains module scripts.
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# DEV_BOT_ROOT is 3 levels up: src/agentic/jetbrains → src/agentic → src → dev-bot root
export DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
