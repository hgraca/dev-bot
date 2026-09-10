#!/usr/bin/env bash
# =============================================================================
# bin/stats.sh — `devbot stats`
#
# Harness-agnostic tool + MCP-server usage report.
#
# The parent command:
#   1. detects the harness (config, overridable with --harness),
#   2. delegates data gathering to the harness adapter
#      (src/harnesses/<harness>/stats.sh), which prints canonical JSON,
#   3. validates that JSON and renders it as a Markdown report.
#
# The canonical JSON contract and how to add an adapter for a new harness are
# documented in docs/harnesses.md (section "Stats adapters").
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Defaults ───────────────────────────────────────────────────────────────────
DEFAULT_DAYS=30
DAYS="${DEFAULT_DAYS}"
SCOPE_ALL=false
HARNESS_OVERRIDE=""

# Where harness adapters live. Overridable for tests / out-of-tree adapters.
HARNESS_DIR="${DEV_BOT_STATS_HARNESS_DIR:-${DEV_BOT_ROOT}/src/harnesses}"
RENDERER="${DEV_BOT_ROOT}/src/_shared/render_stats.py"

_usage() {
  cat <<'EOF'
Usage: devbot stats [--days=N] [--all|-a] [--harness=HARNESS]

Tool and MCP-server usage report, rendered as Markdown.

Options:
  --days=N        Report window in days (default: 30)
  --all, -a       Aggregate every project (default: current project)
  --harness=NAME  Force a harness adapter (default: configured harness)
  --help, -h      Show this help
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days=*)
      DAYS="${1#--days=}"
      shift
      ;;
    --days)
      if [[ $# -lt 2 || "${2:-}" == -* ]]; then
        _fatal "--days requires a value"
        exit 1
      fi
      DAYS="$2"
      shift 2
      ;;
    --all|-a)
      SCOPE_ALL=true
      shift
      ;;
    --harness=*)
      HARNESS_OVERRIDE="${1#--harness=}"
      shift
      ;;
    --harness)
      if [[ $# -lt 2 || "${2:-}" == -* ]]; then
        _fatal "--harness requires a value"
        exit 1
      fi
      HARNESS_OVERRIDE="$2"
      shift 2
      ;;
    --help|-h)
      _usage
      exit 0
      ;;
    *)
      _fatal "Unknown argument: $1"
      _usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${DAYS}" =~ ^[1-9][0-9]*$ ]]; then
  _fatal "Invalid --days value: '${DAYS}' (expected a positive integer)"
  exit 1
fi

# ── Detect the harness and locate its adapter ─────────────────────────────────
harness="${HARNESS_OVERRIDE:-$(_devbot_get_harness "$(pwd)")}"
adapter="${HARNESS_DIR}/${harness}/stats.sh"

if [[ ! -f "${adapter}" ]]; then
  _fatal "No stats adapter for harness '${harness}' (expected ${adapter})"
  exit 1
fi

_info "Gathering ${harness} usage for the last ${DAYS} day(s)…" >&2

# ── Gather: delegate to the harness adapter (canonical JSON on stdout) ────────
adapter_args=(--days "${DAYS}")
if [[ "${SCOPE_ALL}" == "true" ]]; then
  adapter_args+=(--all)
fi

if ! json="$(bash "${adapter}" "${adapter_args[@]}")"; then
  _fatal "Stats adapter for '${harness}' failed"
  exit 1
fi

# ── Validate the canonical JSON before rendering ──────────────────────────────
validation_error="$(printf '%s' "${json}" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except ValueError as exc:
    print(f"invalid JSON: {exc}")
    raise SystemExit

if not isinstance(data, dict):
    print("invalid JSON: top level is not an object")
    raise SystemExit

required = {
    "schema", "harness", "days", "scope", "scope_label",
    "generated_at", "cost_kind", "tools", "mcp_servers",
}
missing = required - set(data)
if missing:
    print("missing keys: " + ", ".join(sorted(missing)))
    raise SystemExit

if data.get("schema") != 1:
    schema = data.get("schema")
    print(f"unsupported schema: {schema!r} (expected 1)")
' 2>&1)"

if [[ -n "${validation_error}" ]]; then
  _fatal "Stats adapter for '${harness}' returned ${validation_error}"
  exit 1
fi

# ── Render: format the canonical JSON as a Markdown report ────────────────────
printf '%s' "${json}" | python3 "${RENDERER}"
