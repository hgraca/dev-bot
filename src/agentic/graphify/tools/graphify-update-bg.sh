#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/tools/graphify-update-bg.sh
# Background worker: runs `graphify update .` with mutex protection.
# Called by OpenCode plugins and Claude Code hooks.
#
# Usage: graphify-update-bg.sh <project-path>
#
# Safety:
# - flock-based mutex prevents concurrent updates
# - Kills any prior stale graphify process for this project
# - Log rotation (tail 50 lines when >100KB)
# - Must be completely silent — no output to terminal
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -uo pipefail

PROJECT_PATH="${1:-$(pwd)}"
PROJECT_PATH="$(cd "${PROJECT_PATH}" 2>/dev/null && pwd)" || exit 0

GRAPHIFY_OUT="${PROJECT_PATH}/graphify-out"
PID_FILE="${GRAPHIFY_OUT}/.graphify-update.pid"
LOG_FILE="${GRAPHIFY_OUT}/.graphify-update.log"
LOCK_FILE="${GRAPHIFY_OUT}/.graphify-update.lock"

# graphify must be installed
if ! command -v graphify >/dev/null 2>&1; then
  exit 0
fi

# graphify-out must exist
if [[ ! -d "${GRAPHIFY_OUT}" ]]; then
  exit 0
fi

mkdir -p "${GRAPHIFY_OUT}"

# ── Mutual exclusion: prevent concurrent graphify updates ──
exec 200>"${LOCK_FILE}"
# audit-25 F2: flock(1) is util-linux (Linux-only) — macOS lacks it. Fall back
# to python fcntl on the inherited fd 200: the lock lives on the open file
# description, so it is still released when this shell exits.
{ flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 0

# ── Kill any prior stale graphify process ──
if [[ -f "${PID_FILE}" ]]; then
  OLD_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${OLD_PID}" ]] && kill -0 "${OLD_PID}" 2>/dev/null; then
    OLD_CMD="$(ps -p "${OLD_PID}" -o command= 2>/dev/null || true)"
    if [[ "${OLD_CMD}" == *graphify* ]]; then
      kill "${OLD_PID}" 2>/dev/null || true
      sleep 0.2
    fi
  fi
  rm -f "${PID_FILE}"
fi

# ── Rotate log ──
if [[ -f "${LOG_FILE}" ]] && [[ "$(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0)" -gt 102400 ]]; then
  tail -n 50 "${LOG_FILE}" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "${LOG_FILE}" || true
fi

# ── Launch graphify update in background ──
(
  echo "${BASHPID}" > "${PID_FILE}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] graphify update started" >> "${LOG_FILE}"
  graphify update . >> "${LOG_FILE}" 2>&1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] graphify update finished (exit $?)" >> "${LOG_FILE}"

  if [[ -f "${PID_FILE}" ]] && [[ "$(cat "${PID_FILE}" 2>/dev/null || true)" == "${BASHPID}" ]]; then
    rm -f "${PID_FILE}"
  fi
) &

BGPID=$!
disown "${BGPID}" 2>/dev/null || true
