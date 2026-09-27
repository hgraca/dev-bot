#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/langs/ts/plugin.sh
# TypeScript / JavaScript language plugin for the forensics tool.
#
# Subcommands: meta | doctor | provision | units
#
# Engine: the TypeScript compiler API (`typescript`), driven by metrics.cjs.
# The project's own typescript is preferred; a pinned scratch install is the
# fallback. Runs in node:22-slim (or the project's declared node image).
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
STORAGE_DIR="${FORENSICS_STORAGE_DIR:-${MODULE_DIR}/../../../storage/forensics}"

_has_typescript() {
  [[ -f "$1/node_modules/typescript/package.json" ]]
}

# <via>\t<root> for the dir containing node_modules/typescript, or non-zero.
_resolve_engine_root() {
  local project="$1"
  if _has_typescript "${project}"; then
    printf 'project\t%s\n' "${project}"
    return 0
  fi
  if _has_typescript "${STORAGE_DIR}/ts"; then
    printf 'scratch\t%s\n' "${STORAGE_DIR}/ts"
    return 0
  fi
  return 1
}

_version_from_package() {
  local file="$1/node_modules/typescript/package.json"
  [[ -f "${file}" ]] || {
    echo "unknown"
    return 0
  }
  python3 - "${file}" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("version", "unknown"))
except Exception:
    print("unknown")
PY
}

_resolve_image() {
  local explicit="${1:-}"
  if [[ -n "${explicit}" ]]; then echo "${explicit}"; return 0; fi
  if [[ -n "${FORENSICS_NODE_IMAGE:-}" ]]; then echo "${FORENSICS_NODE_IMAGE}"; return 0; fi
  echo "node:22-slim"
}

cmd_meta() {
  cat <<'JSON'
{"lang":"ts","extensions":[".ts",".tsx",".js",".jsx",".mjs",".cjs"],"capabilities":["units"],"unit_kinds":["class","method","function"],"metrics":["ccn","loc"],"engine":"typescript"}
JSON
}

cmd_doctor() {
  local project="${PWD}" image=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ $# -ge 2 ]] || {
          echo "ERROR: --project requires a value" >&2
          exit 2
        }
        project="$2"
        shift 2
        ;;
      --image)
        [[ $# -ge 2 ]] || {
          echo "ERROR: --image requires a value" >&2
          exit 2
        }
        image="$2"
        shift 2
        ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    python3 - "${project}" <<'PY'
import json, sys
print(json.dumps({"ok": False, "lang": "ts", "error": "project directory not found: %s" % sys.argv[1]}))
PY
    exit 1
  fi

  local resolved via root
  if ! resolved="$(_resolve_engine_root "${project}")"; then
    python3 - "${project}" <<'PY'
import json, sys
print(json.dumps({"ok": False, "lang": "ts", "project": sys.argv[1], "error": "no TypeScript engine found", "hint": "add typescript to the project, or run: plugin.sh provision"}))
PY
    exit 1
  fi
  via="${resolved%%$'\t'*}"
  root="${resolved#*$'\t'}"
  python3 - "${project}" "$(_resolve_image "${image}")" "${via}" "${root}" "$(_version_from_package "${root}")" <<'PY'
import json, sys
project, image, via, root, version = sys.argv[1:6]
print(json.dumps({"ok": True, "lang": "ts", "project": project, "image": image,
                  "engine": {"via": via, "path": root, "version": version}}))
PY
}

cmd_provision() {
  local dir="${STORAGE_DIR}/ts"
  mkdir -p "${dir}"
  if command -v npm >/dev/null 2>&1; then
    if ! npm --prefix "${dir}" install --silent "typescript@5" >&2; then
      echo "ERROR: npm could not install typescript" >&2
      exit 1
    fi
  elif command -v docker >/dev/null 2>&1; then
    if ! docker run --rm -v "${dir}:/app" -w /app node:22-slim npm install --silent "typescript@5" >&2; then
      echo "ERROR: could not install typescript via the node image" >&2
      exit 1
    fi
  else
    echo "ERROR: npm or docker is required to provision typescript" >&2
    exit 1
  fi
  python3 - "${dir}" "$(_version_from_package "${dir}")" <<'PY'
import json, sys
print(json.dumps({"ok": True, "scratch": sys.argv[1], "version": sys.argv[2]}))
PY
}

cmd_units() {
  local request project
  request="$(cat)"
  if ! project="$(printf '%s' "${request}" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("project") or "")
except Exception:
    sys.exit(3)')"; then
    echo "ERROR: invalid JSON request on stdin" >&2
    exit 1
  fi
  if [[ -z "${project}" || ! -d "${project}" ]]; then
    echo "ERROR: project directory not found: ${project}" >&2
    exit 1
  fi
  # No files: nothing to analyse, and no engine needed.
  if printf '%s' "${request}" | python3 -c 'import json,sys; sys.exit(0 if not (json.load(sys.stdin).get("files") or []) else 1)'; then
    printf '{"ok":true,"units":[],"errors":[]}'
    return 0
  fi

  local resolved via root
  if ! resolved="$(_resolve_engine_root "${project}")"; then
    echo "ERROR: no TypeScript engine found — add typescript to the project, or run: plugin.sh provision" >&2
    exit 1
  fi
  via="${resolved%%$'\t'*}"
  root="${resolved#*$'\t'}"

  local image
  image="$(_resolve_image "")"
  if [[ -z "${image}" || "${image}" =~ [[:space:]] || "${image}" == -* ]]; then
    echo "ERROR: invalid container image reference '${image}'" >&2
    exit 1
  fi

  local -a mounts=(-v "${project}:/app:ro" -v "${PLUGIN_DIR}:/plugin:ro")
  local node_path="/app/node_modules"
  if [[ "${via}" == "scratch" ]]; then
    mounts+=(-v "${root}:/forensics-engine:ro")
    node_path="/forensics-engine/node_modules"
  fi

  local payload
  payload="$(printf '%s' "${request}" | python3 -c '
import json, sys
r = json.load(sys.stdin)
r["project"] = "/app"
print(json.dumps(r))')"

  printf '%s' "${payload}" | docker run --rm -i \
    --network none --read-only --tmpfs /tmp -e HOME=/tmp \
    --user "$(id -u):$(id -g)" \
    -e NODE_PATH="${node_path}" \
    "${mounts[@]}" -w /app "${image}" \
    node /plugin/metrics.cjs
}

case "${1:-}" in
  meta) cmd_meta ;;
  doctor)
    shift
    cmd_doctor "$@"
    ;;
  provision)
    shift
    cmd_provision "$@"
    ;;
  units)
    shift
    cmd_units "$@"
    ;;
  *)
    echo "ERROR: ts plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|units)" >&2
    exit 1
    ;;
esac
