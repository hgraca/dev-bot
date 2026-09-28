#!/usr/bin/env bash
# =============================================================================
# tests/test-project/test-lib.sh
# Shared helpers for the e2e launchers (test-cc.sh / test-oc.sh) and their
# inner scripts.
#
# Each launcher runs its container against an ISOLATED per-run copy of the
# fixture, mounted at /app, so cc and oc (or two runs of the same harness) can
# execute in parallel without racing over .devbot.project.jsonc, the harness
# wiring dirs, or the nested .git — the shared mount previously made every
# parallel run corrupt the others' state (both containers ended up launching
# claudecode). The one shared resource left is the audit-report id: the fixture
# thinking/ dir is bind-mounted so the report lands on the fixture LIVE, so
# reserve_audit_nn() claims the id atomically and the launchers pass it to the
# container (DEVBOT_AUDIT_NN) for parallel runs to stay collision-free.
#
# Sourced by the launchers (host side). Provides:
#   run_dir_create  <fixture> <harness>   — make an isolated copy, print its path
#   run_dir_destroy <run_dir>             — remove the copy (idempotent)
#   reserve_audit_nn <thinking-dir>       — atomically claim the next free audit
#                                            id (empty placeholder), print it
#   sync_run_outputs <run_dir> <fixture> <harness> [<reserved-report>]
#                                          — file the run's logs back
#   composer_cache_args                    — print docker -v/-e args for the host
#                                            composer cache (cross-platform)
#   codebase_memory_prune_run <run-prefix> — host-side: delete this run's entries
#                                            from the shared codebase-memory
#                                            gateway (best-effort; see below)
#   require_host_ollama_for_codebase_engine [install_root] — container-side gate:
#                                            fail only when the installed dev-bot
#                                            selects the codebase-index engine
#                                            (see below)
#   byte_idempotency_report <snap> <live> <log> <files...> — container-side:
#                                            record the double-reinit
#                                            byte-idempotency verdict + per-file
#                                            SHA-256 values for the audit
#                                            (see below)
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
#   - devbot-audit-*.md history (the launchers bind-mount the fixture's
#     thinking/ dir over /app/.agents/memory/thinking, so the container sees
#     the real history and allocates the next NN against it; this only keeps
#     the isolated copy's own listing slim)
#   - vendor/, build/ (regenerated; composer cache is shared instead — but the
#     composer.lock IS carried so `composer install` is reproducible)
# Keeps: source (src/, tests/, composer.json/lock, phpunit.xml...), the
# .devbot.project.jsonc starting point, .agents/memory (vault scaffold) and the
# inner scripts themselves (they run FROM /app).
#
# The run dir lives under $HOME (not /tmp): the shared codebase-memory gateway
# bind-mounts the host's $HOME read-only, so a run dir under /tmp is invisible to
# it and the session-start index would always skip (audit-69 NOTE-1 / audit-70
# FAIL). DEV_BOT_TEST_RUN_ROOT overrides the location.
run_dir_create() {
  local fixture="$1"
  local harness="$2"
  local run_root="${DEV_BOT_TEST_RUN_ROOT:-${HOME}/.cache/devbot-test}"
  mkdir -p "${run_root}"
  local run_dir
  run_dir="$(mktemp -d "${run_root}/devbot-test-${harness}.XXXXXX")"

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
  local run_root="${DEV_BOT_TEST_RUN_ROOT:-${HOME}/.cache/devbot-test}"
  [[ -n "${run_dir}" && "${run_dir}" == "${run_root}/devbot-test-"* ]] \
    && rm -rf "${run_dir}" 2>/dev/null || true
}

# ── Codebase-memory gateway mount ─────────────────────────────────────────────
# The shared gateway bind-mounts ONE host root read-only, at the same absolute
# path inside the container. The container's index hook needs that root to decide
# whether the project is indexable and via which host path. Read it from the
# running container (authoritative), falling back to $HOME — the gateway
# compose's default.
codebase_gateway_mount() {
  local src
  src="$(docker inspect \
    --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
    dev-bot-codebase-memory-mcp 2>/dev/null | head -1)"
  printf '%s' "${src:-${HOME}}"
}

# ── Codebase-memory stale-entry pruning ───────────────────────────────────────
# The shared gateway's index lives on a Docker named volume that OUTLIVES every
# ephemeral run: a run indexes <run_dir>/src, and run_dir_destroy deletes the
# directory while the gateway keeps the now-dangling project entry — so the store
# accumulates one stale `devbot-test-*` project per run (audit-73 §4 / audit-74
# §4). Release this run's entries at teardown by asking the gateway directly over
# MCP, mirroring tools/mcp-index.py's streamable-http handshake (initialize →
# session id → tools/call).
#
# Entries are matched by root_path prefix (the host path the gateway indexed), so
# the gateway-derived project name (path with `/` → `-`) never has to be
# recomputed. Best-effort by design: a gateway that is down, a missing python3 or
# a transport error must never fail a run's cleanup — a stale index entry is
# housekeeping, not a test result.
#
# CODEBASE_MEMORY_MCP_URL overrides the gateway URL (used by the tests).
codebase_memory_prune_run() {
  local prefix="$1"
  # Mirror run_dir_destroy's guard: only a per-run dir under the run root may be
  # pruned. A broad prefix would otherwise match every indexed project on the
  # machine and delete it from the shared named volume — irreversible but for a
  # re-index.
  local run_root="${DEV_BOT_TEST_RUN_ROOT:-${HOME}/.cache/devbot-test}"
  [[ "${prefix}" == "${run_root}/devbot-test-"* ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local url="${CODEBASE_MEMORY_MCP_URL:-}"
  if [[ -z "${url}" ]]; then
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    url="$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1]))["mcp"]["codebase-memory"]["url"])
except Exception:
    pass
' "${repo_root}/src/agentic/codebase-memory/mcp.json" 2>/dev/null)"
  fi
  [[ -n "${url}" ]] || url="http://127.0.0.1:18504/mcp"

  python3 - "${url}" "${prefix}" <<'PY' || true
import json
import sys
import urllib.error
import urllib.request

url, prefix = sys.argv[1], sys.argv[2]
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}
# Bound the page walk: a runaway server must not spin the teardown forever.
_MAX_PAGES = 100


def _post(payload, sid=None, timeout=10):
    req_headers = dict(headers)
    if sid:
        req_headers["Mcp-Session-Id"] = sid
    request = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=req_headers
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.headers.get("Mcp-Session-Id"), response.read()


def _call(sid, name, args, rid):
    _, body = _post(
        {
            "jsonrpc": "2.0",
            "id": rid,
            "method": "tools/call",
            "params": {"name": name, "arguments": args},
        },
        sid,
    )
    result = json.loads(body).get("result") or {}
    text = "".join(
        part.get("text", "")
        for part in result.get("content", [])
        if isinstance(part, dict) and part.get("type") == "text"
    )
    try:
        return json.loads(text)
    except ValueError:
        return result.get("structuredContent") or {}


def _close(sid):
    if not sid:
        return
    request = urllib.request.Request(
        url, method="DELETE", headers={**headers, "Mcp-Session-Id": sid}
    )
    try:
        urllib.request.urlopen(request, timeout=10).close()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError):
        pass


try:
    sid, _ = _post(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "fixture-teardown", "version": "1"},
            },
        }
    )
except (urllib.error.URLError, OSError):
    sys.exit(0)  # gateway not up — nothing to prune, and never break cleanup

try:
    _post({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    bounds = prefix.rstrip("/") + "/"
    names, offset, pages = [], 0, 0
    while pages < _MAX_PAGES:
        data = _call(sid, "list_projects", {"offset": offset, "limit": 100}, 2) or {}
        projects = data.get("projects") or []
        for project in projects:
            root = project.get("root_path", "")
            if (root == prefix or root.startswith(bounds)) and project.get("name"):
                names.append(project["name"])
        if not projects or not data.get("has_more"):
            break
        offset += len(projects)
        pages += 1
    deleted = 0
    for rid, name in enumerate(names, start=10):
        try:
            outcome = _call(sid, "delete_project", {"project": name}, rid)
        except (urllib.error.URLError, OSError, ValueError):
            continue  # one bad delete must not abandon the rest
        if isinstance(outcome, dict) and outcome.get("deleted") is False:
            continue  # the gateway refused it — do not report it as pruned
        deleted += 1
    if deleted:
        print(f"  codebase-memory: pruned {deleted} stale project(s) under {prefix}")
except (urllib.error.URLError, OSError, ValueError):
    # A mid-walk transport error must stay silent: cleanup is best-effort by
    # contract, and a traceback here would masquerade as a test failure.
    pass
finally:
    _close(sid)
PY
}

# ── Audit-report id reservation ───────────────────────────────────────────────
# The fixture thinking/ dir is bind-mounted into the container, so the audit
# writes its report straight onto the fixture — which means the report id is a
# resource two parallel runs share. Claim the next free id atomically: create an
# empty devbot-audit-<NN>.md with noclobber so a racing launcher's claim fails
# and it moves on to the next id. The launcher passes the id to the container
# (DEVBOT_AUDIT_NN); the audit fills that placeholder in place.
reserve_audit_nn() {
  local dir="$1"
  local max=0 f n
  while IFS= read -r f; do
    n="$(basename "${f}" | sed -n 's/^devbot-audit-\([0-9][0-9]*\)\.md$/\1/p')"
    [[ -n "${n}" ]] || continue
    n="$((10#${n}))"
    (( n > max )) && max="${n}"
  done < <(find "${dir}" -maxdepth 1 -name 'devbot-audit-[0-9]*.md' 2>/dev/null)

  n=$(( max + 1 ))
  while :; do
    local candidate
    candidate="${dir}/devbot-audit-$(printf '%02d' "${n}").md"
    if ( set -o noclobber; : > "${candidate}" ) 2>/dev/null; then
      printf '%02d' "${n}"
      return 0
    fi
    n=$(( n + 1 ))
  done
}

# ── Sync-back ────────────────────────────────────────────────────────────────
# The launchers bind-mount the fixture's thinking/ dir at
# /app/.agents/memory/thinking, so the audit report lands on the REAL fixture
# while the run is still going — nothing is copied, renamed, or deleted for it
# here. This function therefore only files the run's LOGS back into the fixture,
# under .agents/logs/<report-id>/ (the report id the launcher reserved) or
# <harness>-<timestamp>/ when no report was written (audit failed / disabled).
sync_run_outputs() {
  local run_dir="$1"
  local fixture="$2"
  local harness="$3"
  local reserved="${4:-}"
  [[ -d "${run_dir}" ]] || return 0

  local thinking="${fixture}/.agents/memory/thinking"
  local logs_base="${fixture}/.agents/logs"

  # The launcher reserved this exact report name before `docker run`; it holds
  # content only once the audit actually wrote it.
  local report=""
  if [[ -n "${reserved}" && -s "${thinking}/${reserved}" ]]; then
    report="${thinking}/${reserved}"
  fi

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
    label="${reserved%.md}"
    echo "  report written via mount → .agents/memory/thinking/${reserved}"
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

# ── Byte-idempotency evidence (container side) ────────────────────────────────
# `devbot reinit` must be byte-idempotent. test-reinit.sh snapshots the
# generated files after reinit #1, runs reinit #2, then calls
# byte_idempotency_report to record the per-file SHA-256 byte values and the
# PASS/FAIL verdict. The log is written BEFORE the harness starts, so start.sh
# rotates it into .agents/logs/rotated/ and the in-session audit reports
# PASS/FAIL from captured evidence instead of NOT-RUN.
#
# Cross-platform: sha256sum (Linux) → shasum -a 256 (macOS) → cksum (POSIX).
_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cksum "$1" | awk '{print $1"-"$2}'
  fi
}

# byte_idempotency_report <snap_dir> <live_dir> <log_file> [file...]
# Compares each snapshotted generated file (reinit #1) with the same file after
# reinit #2 (live_dir). Writes the byte evidence to <log_file>, echoes it to
# stdout, and returns 0 on PASS / 1 on FAIL. Files absent from the snapshot are
# skipped; a snapshotted file that vanished after reinit #2 is a FAIL.
byte_idempotency_report() {
  local snap_dir="$1" live_dir="$2" log_file="$3"
  shift 3
  local -a files=("$@")
  local fail=0 f h1 h2 status
  local -a lines=()

  lines+=("[$(date -u +%Y-%m-%dT%H:%M:%SZ)] byte-idempotency probe (reinit #1 vs reinit #2)")
  for f in "${files[@]}"; do
    [[ -f "${snap_dir}/${f}" ]] || continue
    h1="$(_sha256_file "${snap_dir}/${f}")"
    if [[ -f "${live_dir}/${f}" ]]; then
      h2="$(_sha256_file "${live_dir}/${f}")"
    else
      h2="MISSING"
    fi
    if [[ "${h1}" == "${h2}" ]]; then
      status="MATCH"
    else
      status="DIFF"
      fail=1
    fi
    lines+=("$(printf '%-24s reinit1=%s reinit2=%s %s' "${f}" "${h1}" "${h2}" "${status}")")
  done

  if (( fail == 0 )); then
    lines+=("BYTE-IDEMPOTENCY-PASS: second reinit left all generated files unchanged")
  else
    lines+=("BYTE-IDEMPOTENCY-FAIL: second reinit changed generated files — reinit is not byte-idempotent")
  fi

  printf '%s\n' "${lines[@]}" | tee "${log_file}"
  return "${fail}"
}

# ── Host ollama gate (container side) ─────────────────────────────────────────
# Only the codebase-index engine embeds via the host ollama at :18434 —
# codebase-memory bundles its embeddings, and both mdctx and qmd are zero-ML
# (qmd is BM25-only). The launchers must therefore NOT require host ollama
# unconditionally (the shipped default is codebase-memory + mdctx); this gate
# fires only when the INSTALLED dev-bot selects codebase-index. Invoked from
# test-reinit.sh after install (config exists) and before reinit (which would
# wire the engine). Returns non-zero with a clear message only when the engine
# needs ollama and the API is unreachable.
require_host_ollama_for_codebase_engine() {
  local install_root="${1:-${DEV_BOT_INSTALL_DIR:-$HOME/.local/share/dev-bot}}"
  local funcs="${install_root}/src/_shared/functions.sh"
  local provider=""
  if [[ -f "${funcs}" ]]; then
    provider="$(DEV_BOT_ROOT="${install_root}" bash -c \
      'source "$1" >/dev/null 2>&1; _devbot_get_codebase_provider' _ "${funcs}" 2>/dev/null || true)"
  fi
  [[ -n "${provider}" ]] || provider="codebase-memory"

  if [[ "${provider}" != "codebase-index" ]]; then
    echo "codebase engine: ${provider} — host ollama not required"
    return 0
  fi

  if curl -s --max-time 5 http://localhost:18434/api/tags >/dev/null 2>&1; then
    echo "codebase engine: ${provider} — host ollama reachable at :18434"
    return 0
  fi

  echo "ERROR: codebase_index_provider=codebase-index needs the host ollama at" >&2
  echo "       http://localhost:18434 (the container reaches it via --network host)." >&2
  echo "       On the host, start it with:" >&2
  echo "         docker compose -f src/tools/ollama/docker-compose.yml -f src/tools/ollama/docker-compose.gpu.yml up -d" >&2
  return 1
}
