#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/langs/java/plugin.sh
# Java language plugin for the forensics tool.
#
# Subcommands: meta | doctor | provision | units
#
# Engine: the JDK compiler tree API (com.sun.source), driven by Metrics.java.
# No external dependency — a JDK is all that is needed. Runs on the host `java`
# when present, else eclipse-temurin:21-jdk.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_has_host_java() {
  command -v java >/dev/null 2>&1
}

_java_image() {
  if [[ -n "${FORENSICS_JAVA_IMAGE:-}" ]]; then echo "${FORENSICS_JAVA_IMAGE}"; else echo "eclipse-temurin:21-jdk"; fi
}

cmd_meta() {
  cat <<'JSON'
{"lang":"java","extensions":[".java"],"capabilities":["units"],"unit_kinds":["class","method"],"metrics":["ccn","loc"],"engine":"javac-tree"}
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
print(json.dumps({"ok": False, "lang": "java", "error": "project directory not found: %s" % sys.argv[1]}))
PY
    exit 1
  fi

  local resolved_image="${image:-$(_java_image)}"
  if _has_host_java; then
    local version
    version="$(java -version 2>&1 | head -1)"
    python3 - "${project}" "${version}" <<'PY'
import json, sys
print(json.dumps({"ok": True, "lang": "java", "project": sys.argv[1], "image": None,
                  "engine": {"via": "host", "path": "java", "version": sys.argv[2]}}))
PY
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker image inspect "${resolved_image}" >/dev/null 2>&1; then
    python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
print(json.dumps({"ok": True, "lang": "java", "project": sys.argv[1], "image": sys.argv[2],
                  "engine": {"via": "docker", "path": sys.argv[2], "version": "unknown"}}))
PY
    return 0
  fi

  python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
print(json.dumps({"ok": False, "lang": "java", "project": sys.argv[1], "image": sys.argv[2],
                  "error": "no JDK found", "hint": "install a JDK, or pull %s" % sys.argv[2]}))
PY
  exit 1
}

# Nothing to install: the engine is the JDK itself.
cmd_provision() {
  python3 - <<'PY'
import json
print(json.dumps({"ok": True, "engine": "javac-tree", "note": "no provisioning needed — uses the JDK"}))
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

  if _has_host_java; then
    printf '%s\n' "${absolute[@]}" | java -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dstdout.encoding=UTF-8 \
      "${PLUGIN_DIR}/Metrics.java" "${project}"
    return 0
  fi

  local image
  image="$(_java_image)"
  if [[ -z "${image}" || "${image}" =~ [[:space:]] || "${image}" == -* ]]; then
    echo "ERROR: invalid container image reference '${image}'" >&2
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: no JDK and no docker to run one" >&2
    exit 1
  fi

  local -a container=()
  local file
  for file in "${absolute[@]}"; do
    container+=("/app/${file#"${project}/"}")
  done
  printf '%s\n' "${container[@]}" | docker run --rm -i --network none --read-only --tmpfs /tmp \
    -e LANG=C.UTF-8 \
    --user "$(id -u):$(id -g)" \
    -v "${project}:/app:ro" -v "${PLUGIN_DIR}:/plugin:ro" \
    "${image}" java -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dstdout.encoding=UTF-8 \
    /plugin/Metrics.java /app
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
    echo "ERROR: java plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|units)" >&2
    exit 1
    ;;
esac
