#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode-v2/stats.sh — opencode-v2 stats adapter
#
# Thin wrapper around stats.py. The parent command (`devbot stats`) invokes this
# with `--days N [--all]` and consumes the canonical JSON it prints on stdout.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "${MODULE_DIR}/stats.py" "$@"
