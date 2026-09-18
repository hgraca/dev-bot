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
PROJECT_DIR=""
HARNESS_OVERRIDE=""

# Where harness adapters live. Overridable for tests / out-of-tree adapters.
HARNESS_DIR="${DEV_BOT_STATS_HARNESS_DIR:-${DEV_BOT_ROOT}/src/harnesses}"
RENDERER="${DEV_BOT_ROOT}/src/_shared/render_stats.py"

# Install-level grade matrix written by devbot:grade-tools, and the helper that
# folds it into the canonical JSON. The CSV path is overridable for tests /
# out-of-tree installs.
GRADES_CSV="${DEV_BOT_STATS_GRADES_CSV:-${DEV_BOT_ROOT}/.agents/logs/tools-grades.csv}"
GRADES_HELPER="${DEV_BOT_ROOT}/src/_shared/tool_grades.py"

_usage() {
  cat <<'EOF'
Usage: devbot stats [--days=N] [--project=DIR] [--all|-a] [--harness=HARNESS]

Tool and MCP-server usage report, rendered as Markdown.

Options:
  --days=N        Report window in days (default: 30)
  --project=DIR   Restrict the report to one project directory
  --all, -a       Aggregate every project (the default; kept for compatibility)
  --harness=NAME  Force a harness adapter (default: configured harness)
  --help, -h      Show this help

Without --project the report covers every project recorded by the harness and
every row of the shared grade matrix.
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
    --project=*)
      PROJECT_DIR="${1#--project=}"
      shift
      ;;
    --project)
      if [[ $# -lt 2 || "${2:-}" == -* ]]; then
        _fatal "--project requires a value"
        exit 1
      fi
      PROJECT_DIR="$2"
      shift 2
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

if [[ -n "${PROJECT_DIR}" && "${SCOPE_ALL}" == "true" ]]; then
  _fatal "--project and --all are mutually exclusive"
  exit 1
fi

# Resolve a project directory to an absolute path so it matches the directory
# the harness recorded. A value that is not a directory is passed through
# (a bare <parent>/<folder> label still works for the grades section).
if [[ -n "${PROJECT_DIR}" && -d "${PROJECT_DIR}" ]]; then
  PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
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
if [[ -n "${PROJECT_DIR}" ]]; then
  adapter_args+=(--project "${PROJECT_DIR}")
else
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

# ── Optionally attach the tool-grades block (install-level CSV) ───────────────
# The grade matrix is harness-agnostic, so it is folded in here by the parent
# rather than by an adapter. A missing CSV is silent; a helper failure degrades
# to the ungraded report instead of aborting it.
if [[ -f "${GRADES_CSV}" && -f "${GRADES_HELPER}" ]]; then
  if [[ -n "${PROJECT_DIR}" ]]; then
    grades_scope="current"
    grades_root="${PROJECT_DIR}"
  else
    grades_scope="all"
    grades_root="$(pwd)"
  fi

  if merged="$(printf '%s' "${json}" | python3 "${GRADES_HELPER}" \
      --csv "${GRADES_CSV}" --scope "${grades_scope}" --project-root "${grades_root}")"; then
    json="${merged}"
  else
    # _warn prints to stdout; redirect to stderr so the Markdown report stays clean.
    _warn "could not attach tool grades from ${GRADES_CSV}; continuing without them" >&2
  fi
fi

# ── Render: format the canonical JSON as a Markdown report ────────────────────
printf '%s' "${json}" | python3 "${RENDERER}"
