#!/usr/bin/env bash
# =============================================================================
# src/agentic/docs/tools/ImpactDiagram/impact-diagram.sh
# A use-case map scoped to a git diff. Plain CLI — not exposed over MCP.
# Delegates to create-impact-diagram.py.
#
# Usage:
#   impact-diagram.sh [--project-root <dir>] [--diff <range>] [--output <file>]
#                     [--component <name>] [--title <t>] [--subtitle <s>]
#                     [--copy-visualizer <path>]
# =============================================================================

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "${SOURCE%/*}" && pwd)"

PY_SCRIPT="${SCRIPT_DIR}/create-impact-diagram.py"
if [[ ! -f "${PY_SCRIPT}" ]]; then
  echo "FATAL: create-impact-diagram.py not found at ${PY_SCRIPT}" >&2
  exit 1
fi

exec python3 "${PY_SCRIPT}" "$@"
