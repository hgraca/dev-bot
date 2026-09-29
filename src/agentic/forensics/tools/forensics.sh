#!/usr/bin/env bash
# ---
# description: Mine a repository's git history and per-language static metrics into SQLite, then report hotspots, temporal coupling, ownership, trends and commit-history intelligence.
# ---
# =============================================================================
# src/agentic/forensics/tools/forensics.sh
# Single entry point for the forensics tool.
#
# Usage:
#   forensics.sh <mine|analyse|report|prs|commits|doctor|langs|sources|provision> [options]
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
       [--lang auto|php,ts,java,go] [--granularity file|unit] [--no-defects]
       [--trends] [--trend-interval day|week|month|quarter|year] [--defects <csv>]
       [--modules name=prefix,...] [--all]
                        Walk git history + code units + metrics + commit
                        analysis into the SQLite store. Bounded to the last
                        month by default; --all mines the whole history.
  analyse <db> [--view <view>] [--top N] [--format md|json|csv]
                        Query one view: hotspots, change-rate, coupling,
                        ownership, concentration, unit-ownership,
                        unit-concentration, commit-types, authors, tickets,
                        defects, time-to-fix, fixers, process, releases.
  report <db> [--out <dir|file>] [--format md|json|html] [--with-prs] [--with-analysis]
                        Full Tornhill + commit-history report. A --out path
                        ending .md/.json/.html is the file itself.
  run [<repo>] [--since <date>] [--until <date>] [--out <file>] [--db <path>]
      [--all] [--trends] [--defects <csv>] [--modules name=prefix,...]
                        Mine and report in one step, writing a single
                        self-contained document (activity + analysis section).
  doctor [--project <dir>] [--format md|json]
                        Show each language plugin's resolved engine.
  langs [--format md|json]
                        List registered language plugins and capabilities.
  provision --lang <lang>
                        Install a pinned engine into storage/forensics/<lang>.
  sources [doctor] [--source <name>] [--format md|json]
                        List provider adapters, or doctor their engine (e.g. gh).
  prs [<repo>] [--source github] [--since <date>] [--until <date>]
      [--refresh] [--db <path>] [--format md|json|csv]
                        Merged PR metrics per author + total, from the PR cache.
  commits [<repo>] [--since <date>] [--until <date>] [--format md|json|csv]
                        Commit metrics per author + total, folded via .mailmap.

Every metric is bound to the window `mine` ran with — the last month by default.
Unit ownership is anchored at that window's end date, not its start.

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
  sources) exec python3 "${LIB}" sources "$@" ;;
  prs) exec python3 "${LIB}" prs "$@" ;;
  commits) exec python3 "${LIB}" commits "$@" ;;
  mine) exec python3 "${LIB}" mine "$@" ;;
  analyse) exec python3 "${LIB}" analyse "$@" ;;
  report) exec python3 "${LIB}" report "$@" ;;
  run) exec python3 "${LIB}" run "$@" ;;
  provision) exec python3 "${LIB}" provision "$@" ;;
  *)
    echo "ERROR: unknown command '${command}'" >&2
    usage >&2
    exit 2
    ;;
esac
