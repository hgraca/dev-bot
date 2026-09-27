#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/langs/go/plugin.sh
# Go language plugin for the forensics tool.
#
# Subcommands: meta | doctor | provision | units
#
# Engine: the Go standard library (go/ast), driven by metrics.go. Runs on a host
# `go` toolchain when present, else golang:1.22-alpine (provision pulls it).
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_has_host_go() {
  command -v go >/dev/null 2>&1
}

_go_image() {
  if [[ -n "${FORENSICS_GO_IMAGE:-}" ]]; then echo "${FORENSICS_GO_IMAGE}"; else echo "golang:1.22-alpine"; fi
}

cmd_meta() {
  cat <<'JSON'
{"lang":"go","extensions":[".go"],"capabilities":["units"],"unit_kinds":["function","method"],"metrics":["ccn","loc"],"engine":"go/ast"}
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
print(json.dumps({"ok": False, "lang": "go", "error": "project directory not found: %s" % sys.argv[1]}))
PY
    exit 1
  fi

  local resolved_image="${image:-$(_go_image)}"
  if _has_host_go; then
    python3 - "${project}" "$(go version)" <<'PY'
import json, sys
print(json.dumps({"ok": True, "lang": "go", "project": sys.argv[1], "image": None,
                  "engine": {"via": "host", "path": "go", "version": sys.argv[2]}}))
PY
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker image inspect "${resolved_image}" >/dev/null 2>&1; then
    python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
print(json.dumps({"ok": True, "lang": "go", "project": sys.argv[1], "image": sys.argv[2],
                  "engine": {"via": "docker", "path": sys.argv[2], "version": "unknown"}}))
PY
    return 0
  fi

  python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
print(json.dumps({"ok": False, "lang": "go", "project": sys.argv[1], "image": sys.argv[2],
                  "error": "no Go toolchain found", "hint": "install Go, or run: plugin.sh provision"}))
PY
  exit 1
}

cmd_provision() {
  if _has_host_go; then
    python3 - <<'PY'
import json
print(json.dumps({"ok": True, "engine": "go/ast", "note": "host go toolchain present"}))
PY
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: a host go toolchain or docker is required" >&2
    exit 1
  fi
  local image
  image="$(_go_image)"
  if ! docker pull "${image}" >&2; then
    echo "ERROR: could not pull ${image}" >&2
    exit 1
  fi
  python3 - "${image}" <<'PY'
import json, sys
print(json.dumps({"ok": True, "engine": "go/ast", "image": sys.argv[1]}))
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

  local -a absolute=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && absolute+=("${line}")
  done < <(printf '%s' "${request}" | python3 -c '
import json, os, sys
r = json.load(sys.stdin)
project = r.get("project") or ""
for rel in r.get("files") or []:
    print(os.path.join(project, rel))')

  if [[ ${#absolute[@]} -eq 0 ]]; then
    printf '{"ok":true,"units":[],"errors":[]}'
    return 0
  fi

  if _has_host_go; then
    GO111MODULE=off go run "${PLUGIN_DIR}/metrics.go" "${project}" "${absolute[@]}"
    return 0
  fi

  local image
  image="$(_go_image)"
  if [[ -z "${image}" || "${image}" =~ [[:space:]] || "${image}" == -* ]]; then
    echo "ERROR: invalid container image reference '${image}'" >&2
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: no Go toolchain and no docker to run one" >&2
    exit 1
  fi

  local -a container=()
  local file
  for file in "${absolute[@]}"; do
    container+=("/app/${file#"${project}/"}")
  done
  docker run --rm --network none --read-only --tmpfs /tmp:exec \
    -e HOME=/tmp -e GOCACHE=/tmp/gocache -e GO111MODULE=off \
    --user "$(id -u):$(id -g)" \
    -v "${project}:/app:ro" -v "${PLUGIN_DIR}:/plugin:ro" \
    "${image}" go run /plugin/metrics.go /app "${container[@]}"
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
    echo "ERROR: go plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|units)" >&2
    exit 1
    ;;
esac
