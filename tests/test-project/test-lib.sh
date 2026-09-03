#!/usr/bin/env bash
# =============================================================================
# tests/test-project/test-lib.sh
# Shared host-side helpers for the e2e launchers (test-cc.sh / test-oc.sh).
#
# Each launcher now runs its container against an ISOLATED per-run copy of the
# fixture, mounted at /app, so cc and oc (or two runs of the same harness) can
# execute in parallel without racing over .devbot.project.jsonc, the harness
# wiring dirs, the nested .git, or the audit-report NN sequence — the shared
# mount previously made every parallel run corrupt the others' state (both
# containers ended up launching claudecode).
#
# Sourced by the launchers (host side). Provides:
#   run_dir_create  <fixture> <harness>   — make an isolated copy, print its path
#   run_dir_destroy <run_dir>             — remove the copy (idempotent)
#   sync_run_outputs <run_dir> <fixture> <harness> — copy report + logs back
#   composer_cache_args                    — print docker -v/-e args for the host
#                                            composer cache (cross-platform)
#
# GATE: must run on Linux and macOS (no GNU-only tools).
# =============================================================================

# ── Composer cache (cross-platform) ───────────────────────────────────────────
# The fixture is a PHP/composer kata; sharing the HOST composer cache into the
# container means `composer install` inside the container never re-downloads
# packages. The cache location differs per OS and per setup:
#   - composer's own answer wins: `composer config --global cache-dir`
#   - else Linux:  ~/.cache/composer        (composer v2 XDG default)
#   - else macOS:  ~/Library/Caches/composer
#   - env override COMPOSER_CACHE_DIR wins over everything
# Returns a list of docker args ("-v <host>:<guest> -e COMPOSER_CACHE_DIR=<guest>")
# or an empty string when no host cache exists (mount skipped gracefully).
_composer_cache_host_dir() {
  local dir=""
  if [[ -n "${COMPOSER_CACHE_DIR:-}" && -d "${COMPOSER_CACHE_DIR}" ]]; then
    dir="${COMPOSER_CACHE_DIR}"
  elif command -v php >/dev/null 2>&1 \
    && [[ -x "./composer" || -x "${SCRIPT_DIR}/composer" ]]; then
    local composer_bin="./composer"
    [[ -x "${composer_bin}" ]] || composer_bin="${SCRIPT_DIR}/composer"
    dir="$( (cd "${SCRIPT_DIR}" 2>/dev/null && "${composer_bin}" config --global cache-dir 2>/dev/null) | head -1 )"
    [[ -n "${dir}" && -d "${dir}" ]] || dir=""
  fi
  if [[ -z "${dir}" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      [[ -d "$HOME/Library/Caches/composer" ]] && dir="$HOME/Library/Caches/composer"
    else
      [[ -d "$HOME/.cache/composer" ]] && dir="$HOME/.cache/composer"
    fi
  fi
  printf '%s' "${dir}"
}

composer_cache_args() {
  local host_dir guest_dir
  host_dir="$(_composer_cache_host_dir)"
  [[ -n "${host_dir}" ]] || { echo ""; return 0; }
  guest_dir="/home/ubuntu/.cache/composer"
  mkdir -p "${host_dir}" 2>/dev/null || true
  # Env var is only meaningful when the cache is actually mounted — without the
  # mount it would silently point composer at an empty container-local dir.
  printf '%s' "-v ${host_dir}:${guest_dir} -e COMPOSER_CACHE_DIR=${guest_dir}"
}

# ── Isolated per-run copy ─────────────────────────────────────────────────────
# Copies the fixture to a fresh temp dir, excluding whatever a run regenerates
# or should not carry:
#   - .git (the inner script creates its own throwaway repo)
#   - .agents/{agents,commands,skills,tools,logs} (reinit rewires them)
#   - .claude/, .opencode/, opencode.jsonc, .mcp.json, AGENTS.md, CLAUDE.md
#     (devbot reinit rewires them per harness)
#   - graphify-out/ (rebuilt by reinit)
#   - devbot-audit-*.md history (report NN is allocated fresh on sync-back)
#   - vendor/, build/ (regenerated; composer cache is shared instead — but the
#     composer.lock IS carried so `composer install` is reproducible)
# Keeps: source (src/, tests/, composer.json/lock, phpunit.xml...), the
# .devbot.project.jsonc starting point, .agents/memory (vault scaffold) and the
# inner scripts themselves (they run FROM /app).
run_dir_create() {
  local fixture="$1"
  local harness="$2"
  local run_dir
  run_dir="$(mktemp -d "${TMPDIR:-/tmp}/devbot-test-${harness}.XXXXXX")"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git' \
      --exclude '.agents/agents' --exclude '.agents/commands' \
      --exclude '.agents/skills' --exclude '.agents/tools' \
      --exclude '.agents/logs' \
      --exclude '.agents/memory/thinking/devbot-audit-*.md' \
      --exclude '.claude' --exclude '.opencode' \
      --exclude 'opencode.jsonc' --exclude '.mcp.json' \
      --exclude 'AGENTS.md' --exclude 'CLAUDE.md' \
      --exclude 'graphify-out' --exclude 'vendor' --exclude 'build' \
      "${fixture}/" "${run_dir}/"
  else
    # Fallback without rsync (macOS ships rsync, but keep a cp fallback).
    cp -a "${fixture}/." "${run_dir}/"
    local p
    for p in .git .claude .opencode opencode.jsonc .mcp.json AGENTS.md CLAUDE.md \
      graphify-out vendor build \
      .agents/agents .agents/commands .agents/skills .agents/tools .agents/logs; do
      # SC2115 guard: run_dir always comes from mktemp, never empty or "/".
      rm -rf "${run_dir:?}/${p}" 2>/dev/null || true
    done
    rm -f "${run_dir:?}"/.agents/memory/thinking/devbot-audit-*.md 2>/dev/null || true
  fi
  printf '%s' "${run_dir}"
}

run_dir_destroy() {
  local run_dir="$1"
  [[ -n "${run_dir}" && "${run_dir}" == "${TMPDIR:-/tmp}/devbot-test-"* ]] \
    && rm -rf "${run_dir}" 2>/dev/null || true
}

# ── Sync-back ────────────────────────────────────────────────────────────────
# After the container exits, copy the run's durable outputs back into the real
# fixture:
#   - the audit report  → .agents/memory/thinking/devbot-audit-<nextNN>.md
#   - all devbot logs   → .agents/logs/<report-name-id>/<log files>
#   - the harness logs  → .agents/logs/<report-name-id>/harness/<files>
# Report NN is allocated as the next free integer on the REAL tree, so parallel
# runs (each of which wrote devbot-audit-01.md inside its isolated copy) never
# clobber each other. When no report was produced (audit failed / oc audit
# still disabled), logs land under .agents/logs/<harness>-<timestamp>/.
sync_run_outputs() {
  local run_dir="$1"
  local fixture="$2"
  local harness="$3"
  [[ -d "${run_dir}" ]] || return 0

  local thinking="${fixture}/.agents/memory/thinking"
  local logs_base="${fixture}/.agents/logs"

  # The run wrote devbot-audit-01.md inside its isolated copy (history was
  # excluded). Find the newest report it produced.
  local report=""
  report="$(find "${run_dir}/.agents/memory/thinking" -name 'devbot-audit-*.md' \
    2>/dev/null | sort | tail -1)"

  # Collect the run's logs BEFORE deciding where they land, so we never create
  # empty dirs on the real tree (the fixture is deliberately slim).
  local -a devbot_logs=()
  if [[ -d "${run_dir}/.agents/logs" ]]; then
    while IFS= read -r -d '' f; do
      devbot_logs+=("${f}")
    done < <(find "${run_dir}/.agents/logs" -type f \( -name '*.log' -o -name '*.jsonl' \) \
      -not -path '*/harness/*' -print0 2>/dev/null)
  fi
  local has_harness=0
  [[ -d "${run_dir}/.agents/logs/harness" ]] && has_harness=1

  local label=""
  if [[ -n "${report}" ]]; then
    # Allocate next free NN on the real tree. Force base-10: bash treats
    # "08"/"09" as invalid octal in arithmetic comparisons.
    mkdir -p "${thinking}"
    local next_nn=1 max_nn=0
    while IFS= read -r f; do
      local n
      n="$(basename "${f}" | sed -n 's/^devbot-audit-\([0-9][0-9]*\)\.md$/\1/p')"
      if [[ -n "${n}" ]]; then
        n="$((10#${n}))"
        (( n > max_nn )) && max_nn="${n}"
      fi
    done < <(find "${thinking}" -maxdepth 1 -name 'devbot-audit-*.md' 2>/dev/null)
    next_nn=$(( max_nn + 1 ))
    label="devbot-audit-$(printf '%02d' "${next_nn}")"
    cp "${report}" "${thinking}/${label}.md"
    echo "  synced report → .agents/memory/thinking/${label}.md"
    # Consume the source so a second sync_run_outputs call (e.g. trap + explicit
    # cleanup) cannot re-copy it under a new NN.
    rm -f "${report}" 2>/dev/null || true
  elif (( ${#devbot_logs[@]} > 0 )) || (( has_harness )); then
    # No report (audit failed / oc audit still disabled) but there are logs —
    # keep them under a harness-timestamped dir rather than losing them.
    label="${harness}-$(date +%Y%m%d-%H%M%S)"
    echo "  WARN: no devbot-audit report found in the run — logging under ${label}/"
  else
    return 0  # nothing to sync; leave the slim fixture untouched
  fi

  # Copy the run's devbot logs (if any) into the label dir.
  if (( ${#devbot_logs[@]} > 0 )); then
    mkdir -p "${logs_base}/${label}"
    local f
    for f in "${devbot_logs[@]}"; do
      cp "${f}" "${logs_base}/${label}/" 2>/dev/null || true
    done
  fi

  # Harness logs staged by the inner script under .agents/logs/harness/.
  if (( has_harness )); then
    mkdir -p "${logs_base}/${label}/harness"
    cp -R "${run_dir}/.agents/logs/harness/." "${logs_base}/${label}/harness/" \
      2>/dev/null || true
  fi
}
