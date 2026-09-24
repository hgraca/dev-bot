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
# mounted at /refactor and put on PYTHONPATH, and the plugin directory is mounted
# read-only at /plugin so ops.py can be run without writing into /refactor.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFACTOR_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
STORAGE_DIR="${REFACTOR_STORAGE_DIR:-${REFACTOR_DIR}/../../../storage/refactor}"

cmd_meta() {
  cat <<'JSON'
{"lang":"py","extensions":[".py"],"ops":["rename-symbol","extract-method","extract-variable","inline","encapsulate-field","add-argument","remove-argument","move-module","remove-unused-imports","privatise"],"requires":{"rename-symbol":["from","to"],"extract-method":["file","start","end","to"],"extract-variable":["file","start","end","to"],"inline":["from"],"encapsulate-field":["file","from"],"add-argument":["file","from","to","index"],"remove-argument":["file","from","index"],"move-module":["file","to"],"remove-unused-imports":["file"],"privatise":["file","from"]},"risks":{"rename-symbol":"rename","extract-method":"extract","extract-variable":"extract","inline":"inline","encapsulate-field":"cleanup","add-argument":"signature","remove-argument":"signature","move-module":"move","remove-unused-imports":"cleanup","privatise":"cleanup"}}
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

  local op
  op="$(printf '%s' "${request}" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("op") or "")')"

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
    -v "${PLUGIN_DIR}:/plugin:ro" \
    -e PYTHONPATH=/refactor:/plugin \
    -e REFACTOR_PROJECT_DIR=/app \
    -w /refactor "${image}" python /plugin/ops.py)"

  # The scans look for the old *name*, so they only apply to a rename.
  local string_hits='{"hits": []}' remaining="0"
  if [[ "${op}" == "rename-symbol" ]]; then
    # A name held in a string is invisible to rope's rename, so the report
    # carries what it left behind rather than dropping it silently. Not a
    # `warning`: this is actionable on success too.
    string_hits="$(printf '%s' "${request}" | python3 "${PLUGIN_DIR}/scan.py" 2>/dev/null || echo '{"hits": []}')"

    # Confirm the apply finished: scan the tree for identifier occurrences of the
    # old name that the rename could not reach. A partial rename — a reference
    # rope could not resolve — shows up here rather than downstream. It reads the
    # whole scope again, so a project can opt out with REFACTOR_SKIP_VERIFY=1.
    if [[ "${mode}" == "apply" && -z "${REFACTOR_SKIP_VERIFY:-}" ]]; then
      remaining="$(printf '%s' "${request}" | python3 -c '
import json, sys
r = json.load(sys.stdin)
r["kind"] = "names"
print(json.dumps(r))' | python3 "${PLUGIN_DIR}/scan.py" 2>/dev/null |
        python3 -c 'import json, sys; print(len(json.load(sys.stdin).get("hits") or []))' 2>/dev/null || echo 0)"
    fi
  fi

  printf '%s' "${output}" | REFACTOR_STRING_HITS="${string_hits}" REFACTOR_REMAINING="${remaining}" python3 -c '
import json, os, sys

raw = sys.stdin.read()
try:
    result = json.loads(raw)
except ValueError:
    sys.stdout.write(raw)
    raise SystemExit

if result.get("ok"):
    try:
        hits = json.loads(os.environ.get("REFACTOR_STRING_HITS") or "{}").get("hits") or []
    except ValueError:
        hits = []
    if hits:
        result["string_references"] = hits

    try:
        remaining = int(os.environ.get("REFACTOR_REMAINING") or "0")
    except ValueError:
        remaining = 0
    if remaining:
        result["remaining_changes"] = remaining
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
