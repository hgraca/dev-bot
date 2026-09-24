#!/usr/bin/env bash
# Thin CLI wrapper for the module-docs gather helper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/gather-module-docs.py" "$@"
