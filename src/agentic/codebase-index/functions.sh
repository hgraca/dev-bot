#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/functions.sh
# Shared helpers for codebase-index module scripts (install.sh, update.sh, init.sh).
# Source this file, then call the functions.
# =============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Ollama models required by codebase-index.
# Shared between install.sh and update.sh.
LOCAL_MODELS=(
  "nomic-embed-text:latest"
)

# ── Stale-index migration ─────────────────────────────────────────────────────
#
# A package upgrade can bump the index's on-disk schema (call-graph resolution
# and parser versions). When it does, the package marks the existing index
# "migration-required" and every retrieval tool fails with INDEX_UNAVAILABLE
# until the index is rebuilt — while index_status still reports it as
# "compatible" (that check only covers provider/model, not the migration
# versions).
#
# The package has no cheap freshness command: its own check hashes every file
# in the project before comparing schema versions, which is exactly what makes
# reinit hang. So we read the index DB's stored schema versions directly
# (milliseconds) and compare them to the versions the installed package
# expects. A reindex is then only spawned — detached — when the schema is
# stale, so reinit never blocks. Gated on the index already existing: init
# never builds one from scratch (the package's auto-index does that at session
# start).

# Print the highest-versioned package dir in the npx cache, or nothing.
# `npm_config_cache` is honoured (custom cache dir / .npmrc `cache=`).
# Numeric field sort keeps this POSIX-portable (`sort -V` is not available on
# macOS/BSD by default).
_codebase_index_pkg_from_npx_cache() {
  local cache_dir="${npm_config_cache:-${HOME}/.npm}"
  local d v lines=""
  for d in "${cache_dir}"/_npx/*/node_modules/opencode-codebase-index; do
    [[ -f "${d}/dist/cli.js" && -f "${d}/package.json" ]] || continue
    v="$(grep -m1 '"version"' "${d}/package.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
    [[ -n "${v}" ]] || continue
    lines+="${v}"$'\t'"${d}"$'\n'
  done
  [[ -n "${lines}" ]] || return 0
  printf '%s' "${lines}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-
}

# Locate the package the MCP server runs (npx-latest), to read its expected
# schema versions. The npx cache is where the MCP launch resolves it; a global
# install is the fallback. DEV_BOT_CODEBASE_INDEX_PKG_DIR overrides (tests).
_codebase_index_package_dir() {
  local dir="${DEV_BOT_CODEBASE_INDEX_PKG_DIR:-}"
  if [[ -n "${dir}" ]]; then
    [[ -f "${dir}/dist/cli.js" ]] || return 1
    printf '%s' "${dir}"
    return 0
  fi

  local best=""
  best="$(_codebase_index_pkg_from_npx_cache)"
  if [[ -z "${best}" ]] && command -v npm >/dev/null 2>&1; then
    local global_root=""
    global_root="$(npm root -g 2>/dev/null || true)"
    if [[ -n "${global_root}" && -f "${global_root}/opencode-codebase-index/dist/cli.js" ]]; then
      best="${global_root}/opencode-codebase-index"
    fi
  fi

  [[ -n "${best}" && -f "${best}/dist/cli.js" ]] || return 1
  printf '%s' "${best}"
}

# Read one metadata value from the index DB (read-only). python3 ships the
# sqlite3 module and is a dev-bot prerequisite; the sqlite3 CLI is not.
_codebase_index_metadata() {
  python3 - "$1" "$2" <<'PY'
import sqlite3, sys
try:
    con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    row = con.execute("SELECT value FROM metadata WHERE key = ?", (sys.argv[2],)).fetchone()
    sys.stdout.write(row[0] if row and row[0] is not None else "")
except Exception:
    pass
PY
}

# Report the index's schema state against the installed package:
#   0 = current, 1 = stale (migration required), 2 = cannot determine.
_codebase_index_schema_state() {
  local project_dir="$1" harness_dir="$2"
  local index_dir="${project_dir}/${harness_dir}/index"
  local db="${index_dir}/codebase.db"

  [[ -f "${db}" ]] || return 2

  # The current branch's catalog id is the newest file-hashes.<id>.json the
  # indexer wrote; the migration-version metadata keys are suffixed with it.
  #
  # LIMITATION: the catalog id is the package's internal hash of the branch
  # identity, which we cannot reproduce here, so the newest file is only a
  # proxy for "the branch we are on". If another branch was indexed more
  # recently (e.g. a checkout with no session since), a stale current-branch
  # catalog can be reported as current. A robust fix needs the package to
  # expose its current catalog id or a cheap freshness reason.
  local f newest="" catalog
  for f in "${index_dir}"/file-hashes.*.json; do
    [[ -f "${f}" ]] || continue
    if [[ -z "${newest}" || "${f}" -nt "${newest}" ]]; then
      newest="${f}"
    fi
  done
  [[ -n "${newest}" ]] || return 2
  catalog="$(basename "${newest}")"
  catalog="${catalog#file-hashes.}"
  catalog="${catalog%.json}"

  local pkg
  pkg="$(_codebase_index_package_dir)" || return 2

  # These four (constant, metadata-key prefix) pairs mirror the package's
  # areBranchMigrationVersionsCurrent(). A package release that adds or renames
  # a migration version must be reflected here, or a stale index could be
  # reported as current.
  local pair const meta expected stored
  for pair in \
    "CALL_GRAPH_RESOLUTION_VERSION:index.callGraphResolutionVersion" \
    "SWIFT_PARSER_VERSION:index.parser.swiftVersion" \
    "METAL_PARSER_VERSION:index.parser.metalVersion" \
    "SYMBOL_EXTRACTOR_VERSION:index.symbolExtractorVersion"; do
    const="${pair%%:*}"
    meta="${pair##*:}"
    expected="$(grep -oE "${const}[[:space:]]*=[[:space:]]*\"[0-9]+\"" "${pkg}/dist/cli.js" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)"
    [[ -n "${expected}" ]] || return 2
    stored="$(_codebase_index_metadata "${db}" "${meta}.${catalog}")"
    [[ -n "${stored}" ]] || return 2
    [[ "${stored}" == "${expected}" ]] || return 1
  done
  return 0
}

# Ensure an existing index is up to date, spawning a detached reindex when it
# is not. Never blocks init and never fails it.
_codebase_index_reindex_if_stale() {
  local project_dir="$1" harness_dir="$2" host="$3"

  [[ -d "${project_dir}/${harness_dir}/index" ]] || return 0

  # `|| state=$?` (not `cmd; state=$?`) so `set -e` does not exit on the
  # non-zero stale/unknown return.
  local state=0
  _codebase_index_schema_state "${project_dir}" "${harness_dir}" || state=$?

  if [[ "${state}" -eq 0 ]]; then
    _ok "codebase index up to date (${harness_dir})"
    return 0
  fi

  if ! command -v npx >/dev/null 2>&1; then
    _skip "npx not available — skipping codebase index reindex (${harness_dir})"
    return 0
  fi

  local log_dir="${project_dir}/.agents/logs"
  local log="${log_dir}/codebase-index-reindex.log"
  # A log-dir problem must not abort init — the whole helper is non-fatal.
  mkdir -p "${log_dir}" 2>/dev/null || return 0

  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ "${state}" -eq 1 ]]; then
    _info "codebase index is out of date (${harness_dir}) — reindexing in the background as of ${ts}"
  else
    _info "codebase index status unknown (${harness_dir}) — reindexing in the background as of ${ts}"
  fi
  _info "  log: ${log}"

  # Detached, silent (output goes to the log) — same pattern as
  # _ensure_ollama_models_detached. Reinit must not wait on the reindex.
  # Concurrent reindexers are serialized by the package's own
  # background-worker lease, so a duplicate spawn is harmless.
  ( nohup npx -y -p opencode-codebase-index cbi index \
      --project "${project_dir}" --host "${host}" >> "${log}" 2>&1 & )
  return 0
}
