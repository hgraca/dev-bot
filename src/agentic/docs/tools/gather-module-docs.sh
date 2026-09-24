#!/usr/bin/env bash
# ---
# description: Gather every module's docs.md into the Jekyll site — one page per module, the /modules index, the nav data and the aggregate pages
# ---
#
# Build-time only: run by `make docs` and the Pages workflow, never invoked by
# an agent — which is why the implementation is a stdlib-only Python helper
# rather than the `.ts`-authoritative shape an agent-facing tool takes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/gather-module-docs.py" "$@"
