#!/usr/bin/env bash
# ---
# description: Findings store CLI — check/add/list/stale, and the gate that answers PASS, REVIEW or BLOCK for a diff against what security already knows
# ---
# =============================================================================
# src/agentic/security/scripts/findings.sh
#
# Thin wrapper: the work is in findings.py, which needs python3 (already a
# toolkit dependency). This exists so the module exposes one `.sh` CLI, the way
# every other devbot tool does.
#
#   findings.sh check            validate the store and summarise it
#   findings.sh add < record     append one JSON record
#   findings.sh list --file …    query; this is the advice surface
#   findings.sh stale            findings older than the file they describe
#   findings.sh gate --base main PASS/REVIEW/BLOCK for a diff (exit 0/1/2)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    printf 'ERROR: python3 is required by the findings store\n' >&2
    exit 3
fi

exec python3 "${SCRIPT_DIR}/findings.py" "$@"
