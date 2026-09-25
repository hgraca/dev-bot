#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/langs/ts/plugin.sh
# TypeScript language plugin for the refactor tool.
#
# Subcommands: meta | doctor | provision | plan | apply
#
# Engine: ts-morph, which drives the TypeScript compiler. Its rename() is
# type-aware and updates every reference across the project, so one run does the
# whole job — there is no per-rule step model here, unlike the PHP plugin where
# Rector needs one rule at a time.
#
# Route: the project is mounted at /app; the ts-morph toolchain lives in the
# shared scratch dir and is mounted at /refactor, with rename.mjs beside it so
# Node resolves the module.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFACTOR_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
STORAGE_DIR="${REFACTOR_STORAGE_DIR:-${REFACTOR_DIR}/../../../storage/refactor}"

cmd_meta() {
  cat <<'JSON'
{"lang":"ts","extensions":[".ts",".tsx",".js",".jsx"],"ops":["rename-symbol","move-file","move-member","privatize-members","remove-unused-locals","remove-unused-params"],"requires":{"rename-symbol":["from","to"],"move-file":["file","to"],"move-member":["class","from","to"],"privatize-members":[],"remove-unused-locals":["file"],"remove-unused-params":["file"]},"risks":{"rename-symbol":"rename","move-file":"move","move-member":"move","privatize-members":"cleanup","remove-unused-locals":"cleanup","remove-unused-params":"signature"}}
JSON
}

# The scratch toolchain root, or non-zero when it is not installed.
_engine_root() {
  local root="${STORAGE_DIR}/ts"
  [[ -d "${root}/node_modules/ts-morph" ]] || return 1
  echo "${root}"
}

_resolve_image() {
  local explicit="$1"
  if [[ -n "${explicit}" ]]; then echo "${explicit}"; return 0; fi
  if [[ -n "${REFACTOR_NODE_IMAGE:-}" ]]; then echo "${REFACTOR_NODE_IMAGE}"; return 0; fi
  # A static rename needs no project-native toolchain, unlike Rector's PHP case.
  echo "node:22-slim"
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
    printf '{"ok":false,"lang":"ts","project":"%s","image":"%s","error":"no ts-morph engine found","hint":"run: plugin.sh provision"}\n' \
      "${project}" "${resolved_image}"
    exit 1
  fi

  local version
  version="$(node -e 'console.log(require(process.argv[1]).version)' \
    "${root}/node_modules/ts-morph/package.json" 2>/dev/null || echo unknown)"

  printf '{"ok":true,"lang":"ts","project":"%s","image":"%s","engine":{"via":"scratch","path":"%s","version":"%s"}}\n' \
    "${project}" "${resolved_image}" "${root}" "${version}"
}

# Install the pinned toolchain into the shared scratch dir. npm is the official
# channel for both packages.
cmd_provision() {
  local dir="${STORAGE_DIR}/ts"
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm is required to provision the ts-morph engine" >&2
    exit 1
  fi

  mkdir -p "${dir}"
  if ! npm --prefix "${dir}" install --silent ts-morph typescript >&2; then
    echo "ERROR: npm could not install ts-morph" >&2
    exit 1
  fi

  printf '{"ok":true,"scratch":"%s"}\n' "${dir}"
}

cmd_run() {
  local mode="$1" request
  request="$(cat)"

  # The core validates the op and its required fields against `meta`; the driver
  # validates them again from the request, so the plugin adds nothing here and
  # cannot drift from the contract it declares (matching the Python plugin).
  local project image root

  project="${REFACTOR_PROJECT:-${PWD}}"

  if ! root="$(_engine_root)"; then
    echo '{"ok":false,"error":"no ts-morph engine found","hint":"run: plugin.sh provision"}' >&2
    exit 1
  fi

  image="$(_resolve_image "${REFACTOR_NODE_IMAGE:-}")"

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

  # Run as the invoking user: the engine writes new paths (a move creates its
  # destination), and a root-owned file in the caller's tree is uneditable.
  printf '%s' "${payload}" | docker run --rm -i \
    --user "$(id -u):$(id -g)" \
    -v "${project}:/app${mount_suffix}" \
    -v "${root}:/refactor" \
    -v "${PLUGIN_DIR}/rename.mjs:/refactor/rename.mjs:ro" \
    -e REFACTOR_PROJECT_DIR=/app \
    -w /refactor "${image}" node rename.mjs
}

case "${1:-}" in
  meta)      cmd_meta ;;
  doctor)    shift; cmd_doctor "$@" ;;
  provision) shift; cmd_provision "$@" ;;
  plan)      shift; cmd_run plan ;;
  apply)     shift; cmd_run apply ;;
  *)
    echo "ERROR: ts plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|plan|apply)" >&2
    exit 1
    ;;
esac
