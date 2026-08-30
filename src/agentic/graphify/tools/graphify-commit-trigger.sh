#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/tools/graphify-commit-trigger.sh
# Harness-agnostic commit-trigger bridge for graphify updates.
#
# The harness detects the commit and calls `detect`; on idle/stop it calls
# `check`, which spawns the background update. Dedup, trigger file, TTL, and
# spawn logic live here exactly once — shared by the opencode plugin and the
# claudecode hooks.
#
# Usage:
#   graphify-commit-trigger.sh detect <worktree> <hash>
#   graphify-commit-trigger.sh check  <worktree>
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -uo pipefail

TRIGGER_TTL_MIN=5

CMD="${1:-}"
WORKTREE="${2:-$(pwd)}"

GRAPHIFY_OUT="${WORKTREE}/graphify-out"
TRIGGER_FILE="${GRAPHIFY_OUT}/.graphify-commit-trigger.json"
PROCESSED_FILE="${GRAPHIFY_OUT}/.graphify-commit-processed"
RUNNER="${WORKTREE}/src/agentic/graphify/tools/graphify-update-bg.sh"

case "${CMD}" in
  detect)
    HASH="${3:-}"
    [[ -z "${HASH}" ]] && exit 0

    # Dedup by commit hash
    mkdir -p "${GRAPHIFY_OUT}"
    if [[ -f "${PROCESSED_FILE}" ]] && grep -qFx "${HASH}" "${PROCESSED_FILE}" 2>/dev/null; then
      exit 0
    fi
    echo "${HASH}" >> "${PROCESSED_FILE}"

    # Write trigger
    python3 -c "
import json
data = {'hash': '${HASH}', 'committedAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'}
with open('${TRIGGER_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
    ;;

  check)
    [[ -f "${TRIGGER_FILE}" ]] || exit 0

    # TTL check — discard stale triggers
    TRIGGER_HASH=$(python3 -c "
import json, os, sys, time
with open('${TRIGGER_FILE}') as f:
    data = json.load(f)
age = time.time() - time.mktime(time.strptime(data['committedAt'], '%Y-%m-%dT%H:%M:%SZ'))
if age > ${TRIGGER_TTL_MIN} * 60:
    os.unlink('${TRIGGER_FILE}')
    sys.exit(1)
print(data['hash'])
" 2>/dev/null || true)
    [[ -z "${TRIGGER_HASH}" ]] && exit 0

    # Spawn the background update
    if [[ -f "${RUNNER}" ]]; then
      bash "${RUNNER}" "${WORKTREE}" &
      disown 2>/dev/null || true
    fi

    rm -f "${TRIGGER_FILE}"
    ;;

  *)
    echo "Usage: graphify-commit-trigger.sh detect <worktree> <hash> | check <worktree>" >&2
    exit 1
    ;;
esac

exit 0
