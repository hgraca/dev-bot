#!/usr/bin/env bash
# ---
# description: Mine a repository's git history and per-language static metrics into SQLite, then report hotspots, temporal coupling, ownership, trends and commit-history intelligence.
# ---
# =============================================================================
# src/agentic/forensics/tools/forensics.sh
# Single entry point for the forensics tool.
#
# Usage:
#   forensics.sh <mine|analyse|report|doctor|langs|provision> [options]
#
# A plain CLI, not an MCP tool (the same posture as refactor): the
# `devbot:forensics` skill documents it and an agent runs it as
# `devbot tool forensics <command>`.
#
# JSON never crosses bash: lib/forensics-lib.py resolves the request and renders
# the response. Language specifics live in langs/<lang>/plugin.sh; the core knows
# no language.
#
# GATE: must run on Ubuntu, Fedora and macOS — no GNU-only tools, and no
# `readlink -f` (resolve symlinks by hand).
# =============================================================================

set -euo pipefail

VERSION="0.1.0"

_resolve_self() {
  local target="${BASH_SOURCE[0]}" dir link
  while [[ -L "${target}" ]]; do
    dir="$(cd -P "$(dirname "${target}")" && pwd)"
    link="$(readlink "${target}")"
    [[ "${link}" != /* ]] && link="${dir}/${link}"
    target="${link}"
  done
  cd -P "$(dirname "${target}")" && pwd
}

SCRIPT_DIR="$(_resolve_self)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${MODULE_DIR}/lib/forensics-lib.py"
LANGS_DIR="${FORENSICS_LANGS_DIR:-${MODULE_DIR}/langs}"
export FORENSICS_LANGS_DIR="${LANGS_DIR}"

usage() {
  cat <<'EOF'
forensics — behavioral code analysis, documented by the devbot:forensics skill

Usage:
  forensics <command> [options]

Commands:
  mine [<repo>] [--since <date>] [--until <date>] [--db <path>]
       [--lang auto|php,py,ts] [--granularity file|unit]
                        Walk git history + code units + metrics + commit
                        analysis into the SQLite store.
  analyse <db> [--view <view>] [--top N] [--format md|json]
                        Query one view (hotspots, coupling, ownership,
                        concentration, trends, architecture, history, all).
  report <db> [--out <dir>] [--format md|json]
                        Full Tornhill + commit-history report.
  doctor [--project <dir>] [--format md|json]
                        Show each language plugin's resolved engine.
  langs [--format md|json]
                        List registered language plugins and capabilities.
  provision --lang <lang>
                        Install a pinned engine into storage/forensics/<lang>.

Options:
  --version   show the tool version
  --help, -h  show this help
EOF
}

case "${1:-}" in
  --version)
    echo "forensics ${VERSION}"
    exit 0
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
esac

command="$1"
shift

case "${command}" in
  langs) exec python3 "${LIB}" langs "$@" ;;
  doctor) exec python3 "${LIB}" doctor "$@" ;;
  mine) exec python3 "${LIB}" mine "$@" ;;
  analyse | report | provision)
    echo "ERROR: '${command}' is not implemented yet (Phase 0 in progress)" >&2
    exit 3
    ;;
  *)
    echo "ERROR: unknown command '${command}'" >&2
    usage >&2
    exit 2
    ;;
esac
