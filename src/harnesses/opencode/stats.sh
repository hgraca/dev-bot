#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/stats.sh — opencode stats adapter for `devbot stats`
#
# Thin wrapper around stats.py. The parent command (`devbot stats`) invokes this
# with `--days N [--all]` and consumes the canonical JSON it prints on stdout.
# See docs/harnesses.md ("Stats adapters") for the contract.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "${MODULE_DIR}/stats.py" "$@"
