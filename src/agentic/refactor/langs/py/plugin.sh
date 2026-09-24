#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/langs/py/plugin.sh
# Python language plugin for the refactor tool.
#
# Subcommands: meta | doctor | provision | plan | apply
#
# Engine: rope, the Python refactoring library. Its Rename builds a project-wide
# change set from the symbol table, so one run covers the definition and its
# references — no per-rule steps, and unlike the TypeScript compiler it is not
# fully type-aware, so dynamic construction stays invisible.
#
# Route: the project is mounted at /app; rope lives in the shared scratch dir,
# mounted at /refactor and put on PYTHONPATH, with rename.py beside it.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFACTOR_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
STORAGE_DIR="${REFACTOR_STORAGE_DIR:-${REFACTOR_DIR}/../../../storage/refactor}"

cmd_meta() {
  cat <<'JSON'
{"lang":"py","extensions":[".py"],"ops":["rename-symbol"],"requires":{"rename-symbol":["from","to"]},"risks":{"rename-symbol":"rename"}}
JSON
}

# The scratch toolchain root, or non-zero when rope is not installed.
_engine_root() {
  local root="${STORAGE_DIR}/py"
  [[ -d "${root}/rope" ]] || return 1
  echo "${root}"
}

_resolve_image() {
  local explicit="$1"
  if [[ -n "${explicit}" ]]; then echo "${explicit}"; return 0; fi
  if [[ -n "${REFACTOR_PYTHON_IMAGE:-}" ]]; then echo "${REFACTOR_PYTHON_IMAGE}"; return 0; fi
  echo "python:3.12-slim"
}

cmd_doctor() {
  local project="${PWD}" image=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --image) image="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    printf '{"ok":false,"error":"project directory not found: %s"}\n' "${project}"
    exit 1
  fi

  local resolved_image="$(_resolve_image "${image}")"
  local root
  if ! root="$(_engine_root)"; then
    printf '{"ok":false,"lang":"py","project":"%s","image":"%s","error":"no rope engine found","hint":"run: plugin.sh provision"}\n' \
      "${project}" "${resolved_image}"
    exit 1
  fi

  local version
  version="$(PYTHONPATH="${root}" python3 -c 'import rope; print(getattr(rope, "__version__", "unknown"))' 2>/dev/null || echo unknown)"

  printf '{"ok":true,"lang":"py","project":"%s","image":"%s","engine":{"via":"scratch","path":"%s","version":"%s"}}\n' \
    "${project}" "${resolved_image}" "${root}" "${version}"
}

cmd_provision() {
  local dir="${STORAGE_DIR}/py"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to provision the rope engine" >&2
    exit 1
  fi

  mkdir -p "${dir}"
  if ! python3 -m pip install --quiet --target "${dir}" rope >&2; then
    echo "ERROR: pip could not install rope" >&2
    exit 1
  fi

  printf '{"ok":true,"scratch":"%s"}\n' "${dir}"
}

cmd_run() {
  local mode="$1" request
  request="$(cat)"

  local op from to project image root
  IFS=$'\x1f' read -r op from to < <(printf '%s' "${request}" | python3 -c '
import json, sys
r = json.load(sys.stdin)
print("\x1f".join([str(r.get("op") or ""), str(r.get("from") or ""), str(r.get("to") or "")]))')

  if [[ "${op}" != "rename-symbol" ]]; then
    printf '{"ok":false,"error":"py plugin: unsupported op: %s"}\n' "${op}" >&2
    exit 1
  fi
  if [[ -z "${from}" || -z "${to}" ]]; then
    echo '{"ok":false,"error":"from and to are required"}' >&2
    exit 1
  fi

  project="${REFACTOR_PROJECT:-${PWD}}"

  # The string-reference scan runs on the host (it needs no rope), so carry the
  # host project path in the request for it to read the very tree rope edits.
  request="$(PROJECT="${project}" python3 -c '
import json, os, sys
r = json.load(sys.stdin)
r["project"] = os.environ["PROJECT"]
print(json.dumps(r))' <<< "${request}")"

  if ! root="$(_engine_root)"; then
    echo '{"ok":false,"error":"no rope engine found","hint":"run: plugin.sh provision"}' >&2
    exit 1
  fi

  image="$(_resolve_image "${REFACTOR_PYTHON_IMAGE:-}")"

  # A dry run must not be able to write.
  local mount_suffix="" apply="false"
  if [[ "${mode}" == "apply" ]]; then
    apply="true"
  else
    mount_suffix=":ro"
  fi

  local payload
  payload="$(printf '%s' "${request}" | APPLY="${apply}" python3 -c '
import json, os, sys
r = json.load(sys.stdin)
r["apply"] = os.environ["APPLY"] == "true"
print(json.dumps(r))')"

  local output
  output="$(printf '%s' "${payload}" | docker run --rm -i \
    -v "${project}:/app${mount_suffix}" \
    -v "${root}:/refactor" \
    -v "${PLUGIN_DIR}/rename.py:/refactor/rename.py:ro" \
    -e PYTHONPATH=/refactor \
    -e REFACTOR_PROJECT_DIR=/app \
    -w /refactor "${image}" python rename.py)"

  # A name held in a string is invisible to rope's rename, so the report carries
  # what it left behind rather than dropping it silently. Not a `warning`: this
  # is actionable on success too.
  local string_hits
  string_hits="$(printf '%s' "${request}" | python3 "${PLUGIN_DIR}/string_refs.py" 2>/dev/null || echo '{"hits": []}')"

  printf '%s' "${output}" | REFACTOR_STRING_HITS="${string_hits}" python3 -c '
import json, os, sys

raw = sys.stdin.read()
try:
    result = json.loads(raw)
except ValueError:
    sys.stdout.write(raw)
    raise SystemExit

try:
    hits = json.loads(os.environ.get("REFACTOR_STRING_HITS") or "{}").get("hits") or []
except ValueError:
    hits = []
if hits and result.get("ok"):
    result["string_references"] = hits
sys.stdout.write(json.dumps(result) + "\n")'
}

case "${1:-}" in
  meta)      cmd_meta ;;
  doctor)    shift; cmd_doctor "$@" ;;
  provision) shift; cmd_provision "$@" ;;
  plan)      shift; cmd_run plan ;;
  apply)     shift; cmd_run apply ;;
  *)
    echo "ERROR: py plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|plan|apply)" >&2
    exit 1
    ;;
esac
