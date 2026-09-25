#!/usr/bin/env bash
# ---
# description: Deterministic refactoring across languages (PHP, Python, TypeScript) — rename, extract, inline, move and cleanup ops that update every genuine reference. Dry-run by default; pass --apply to write.
# ---
# =============================================================================
# src/agentic/refactor/tools/refactor/refactor.sh
# Single entry point for the refactor tool.
#
# Usage:
#   refactor.sh <op> [options]
#
# A plain CLI, not an MCP tool: the `devbot:refactor` skill documents it and an
# agent runs it as `devbot tool refactor <op> …`. The language plugin is chosen
# from --file's extension, else from an op only one language declares.
#
# JSON never crosses bash: lib/refactor-lib.py resolves the request, emits it,
# and renders the plugin's response. A plugin is a langs/<lang>/plugin.sh
# subscript; the core knows no language specifics.
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
LIB="${SCRIPT_DIR}/lib/refactor-lib.py"
LANGS_DIR="${REFACTOR_LANGS_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)/langs}"
export REFACTOR_LANGS_DIR="${LANGS_DIR}"

usage() {
  cat <<'EOF'
refactor — deterministic refactoring, documented by the devbot:refactor skill

Usage:
  refactor <op> [options]

  <op> is the refactoring (see the list below). The language is inferred from
  --file, or from an op that only one language declares; otherwise pass --lang.

Options:
  --lang <lang>   force a language plugin (php, py, ts)
  --file <path>   the file declaring the symbol — also picks the language
  --kind <kind>   variant/declaration kind when an op offers several
  --class <name>  class the symbol lives in (ops on members)
  --from <old>    current name (aliases: --method, --property)
  --to <new>      new name (or destination, for a move op)
  --namespace <ns>  namespace, for ops on free functions/constants
  --start <line[:col]>  first line of a range (extract ops)
  --end <line[:col]>    last line of a range (extract ops)
  --index <n>     parameter position (signature ops)
  --default <x>   default expression for an added parameter
  --image <ref>   container image to run the engine in
  --apply         write the change (default: dry-run plan only)
  --json          emit the raw response as JSON
  --force         proceed despite a dirty working tree
  --version       show the tool version
  --help, -h      show this help
EOF
}

if [[ "${1:-}" == "--version" ]]; then
  echo "refactor ${VERSION}"
  exit 0
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  echo
  echo "Refactorings:"
  python3 "${LIB}" ops 2>/dev/null | tr ',' '\n' | sed 's/^ */  /' || true
  exit 0
fi

op="" lang="" file="" kind="" klass="" from="" to="" method="" property=""
namespace="" start="" end="" index="" default="" image=""
apply="false" force="false" format="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply="true"; shift ;;
    --force) force="true"; shift ;;
    --json) format="json"; shift ;;
    --markdown) format="markdown"; shift ;;
    --lang|--file|--kind|--class|--from|--to|--method|--property|--namespace|--start|--end|--index|--default|--image)
      [[ $# -ge 2 ]] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
      case "$1" in
        --lang) lang="$2" ;;
        --file) file="$2" ;;
        --kind) kind="$2" ;;
        --class) klass="$2" ;;
        --from) from="$2" ;;
        --to) to="$2" ;;
        --method) method="$2" ;;
        --property) property="$2" ;;
        --namespace) namespace="$2" ;;
        --start) start="$2" ;;
        --end) end="$2" ;;
        --index) index="$2" ;;
        --default) default="$2" ;;
        --image) image="$2" ;;
      esac
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "ERROR: unknown option '$1'" >&2
      exit 2
      ;;
    *)
      if [[ -z "${op}" ]]; then
        op="$1"
        shift
      else
        echo "ERROR: unexpected argument '$1'" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "${op}" ]]; then
  echo "ERROR: no refactoring given" >&2
  usage >&2
  exit 2
fi

# Refuse to write onto a dirty working tree: an automated rename stacked on top
# of uncommitted work is hard to review and harder to reverse. Untracked files
# are deliberately ignored — a rename does not touch them. A directory that is
# not a git repo has nothing to guard.
if [[ "${apply}" == "true" && "${force}" != "true" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
      echo "ERROR: the git working tree is dirty (uncommitted changes to tracked files) — commit or stash first, or pass --force" >&2
      exit 1
    fi
  fi
fi

err_file="$(mktemp)"
trap 'rm -f "${err_file}"' EXIT

set +e
decision="$(python3 "${LIB}" resolve \
  --op "${op}" \
  --lang "${lang}" \
  --file "${file}" \
  --kind "${kind}" \
  --class "${klass}" \
  --from "${from}" \
  --method "${method}" \
  --property "${property}" \
  --to "${to:-}" \
  --namespace "${namespace}" \
  --start "${start}" \
  --end "${end}" \
  --index "${index}" \
  --default "${default}" \
  --image "${image}" \
  --apply "${apply}" 2>"${err_file}")"
rc=$?
set -e

if [[ ${rc} -ne 0 ]]; then
  cat "${err_file}" >&2
  exit "${rc}"
fi

{ IFS= read -r plugin_dir; IFS= read -r request_json; } < <(
  printf '%s' "${decision}" | python3 "${LIB}" emit
)

mode="plan"
[[ "${apply}" == "true" ]] && mode="apply"

set +e
output="$(printf '%s' "${request_json}" | bash "${plugin_dir}/plugin.sh" "${mode}" 2>"${err_file}")"
rc=$?
set -e

if [[ ${rc} -ne 0 ]]; then
  [[ -s "${err_file}" ]] && cat "${err_file}" >&2
  [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
  echo "ERROR: the refactor plugin failed (exit ${rc})" >&2
  exit 1
fi

set +e
printf '%s' "${output}" | python3 "${LIB}" finish --op "${op}" --format "${format}"
rc=$?
set -e
exit "${rc}"
