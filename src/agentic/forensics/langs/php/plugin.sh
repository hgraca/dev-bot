#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/langs/php/plugin.sh
# PHP language plugin for the forensics tool.
#
# Subcommands:
#   meta      — plugin descriptor for the core's registry
#   doctor    — report the resolved PDepend engine
#   provision — install a pinned PDepend into the shared scratch dir
#   units     — emit code units + complexity for a file list (stdin JSON)
#
# Engine policy: the project's own PDepend (vendor/pdepend/pdepend) is preferred
# — right version, right autoload. A pinned Composer install in the shared
# scratch dir is the fallback. The driver runs in the project's PHP image when
# one can be detected, else a curated php:<version>-cli image.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
STORAGE_DIR="${FORENSICS_STORAGE_DIR:-${MODULE_DIR}/../../../storage/forensics}"

# ── Engine resolution ─────────────────────────────────────────────────────────

_pdepend_version_from_lock() {
  local lock="$1"
  [[ -f "${lock}" ]] || {
    echo "unknown"
    return 0
  }
  python3 - "${lock}" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown"); raise SystemExit
for pkg in data.get("packages", []) + data.get("packages-dev", []):
    if pkg.get("name") == "pdepend/pdepend":
        print(pkg.get("version", "unknown")); raise SystemExit
print("unknown")
PY
}

_has_pdepend() {
  [[ -d "$1/vendor/pdepend/pdepend" && -f "$1/vendor/autoload.php" ]]
}

# The dir containing vendor/ with PDepend, as <via>\t<root>; returns 1 if none.
_resolve_engine_root() {
  local project="$1"
  if _has_pdepend "${project}"; then
    printf 'project\t%s\n' "${project}"
    return 0
  fi
  if _has_pdepend "${STORAGE_DIR}/php"; then
    printf 'scratch\t%s\n' "${STORAGE_DIR}/php"
    return 0
  fi
  return 1
}

# The project's declared PHP version: .php-version wins, then composer.json.
_project_php_version() {
  local project="$1"
  if [[ -f "${project}/.php-version" ]]; then
    tr -d '[:space:]' <"${project}/.php-version"
    return 0
  fi
  if [[ -f "${project}/composer.json" ]]; then
    python3 - "${project}/composer.json" <<'PY'
import json, re, sys
try:
    req = json.load(open(sys.argv[1])).get("require", {}).get("php", "")
except Exception:
    req = ""
m = re.search(r"(\d+\.\d+)", req or "")
print(m.group(1) if m else "")
PY
    return 0
  fi
  echo ""
}

# Precedence: explicit > FORENSICS_PHP_IMAGE > project compose image > php:<ver>-cli
_resolve_image() {
  local project="$1" explicit="${2:-}"
  if [[ -n "${explicit}" ]]; then
    echo "${explicit}"
    return 0
  fi
  if [[ -n "${FORENSICS_PHP_IMAGE:-}" ]]; then
    echo "${FORENSICS_PHP_IMAGE}"
    return 0
  fi

  local compose="" file
  for file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${project}/${file}" ]]; then
      compose="${project}/${file}"
      break
    fi
  done
  if [[ -n "${compose}" ]]; then
    local image
    image="$(python3 - "${compose}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"^\s*image:\s*[\"']?([^\"'\s]+)", text, re.M)
print(m.group(1) if m else "")
PY
)"
    if [[ -n "${image}" ]]; then
      echo "${image}"
      return 0
    fi
  fi

  local version
  version="$(_project_php_version "${project}")"
  if [[ -n "${version}" ]]; then echo "php:${version}-cli"; else echo "php:cli"; fi
}

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_meta() {
  cat <<'JSON'
{"lang":"php","extensions":[".php"],"capabilities":["units","complexity"],"unit_kinds":["class","method"],"metrics":["wmc","ccn","loc","ncloc","dit","ca","ce","cbo","npm"],"engine":"pdepend"}
JSON
}

cmd_doctor() {
  local project="${PWD}" image=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        project="$2"
        shift 2
        ;;
      --image)
        image="$2"
        shift 2
        ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    printf '{"ok":false,"lang":"php","error":"project directory not found: %s"}\n' "${project}"
    exit 1
  fi

  local resolved via root
  if ! resolved="$(_resolve_engine_root "${project}")"; then
    printf '{"ok":false,"lang":"php","project":"%s","error":"no PDepend engine found","hint":"add pdepend/pdepend to the project, or run: plugin.sh provision"}\n' "${project}"
    exit 1
  fi
  via="${resolved%%$'\t'*}"
  root="${resolved#*$'\t'}"

  local version
  version="$(_pdepend_version_from_lock "${root}/composer.lock")"
  if [[ -z "${version}" || "${version}" == "unknown" ]]; then
    version="$(_pdepend_version_from_lock "${project}/composer.lock")"
  fi
  printf '{"ok":true,"lang":"php","project":"%s","image":"%s","engine":{"via":"%s","path":"%s","version":"%s"}}\n' \
    "${project}" "$(_resolve_image "${project}" "${image}")" "${via}" "${root}" "${version}"
}

# Install a pinned PDepend into the shared scratch dir. Composer is the official
# distribution channel.
cmd_provision() {
  local version="${1:-^2.16}"
  local dir="${STORAGE_DIR}/php"

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required to provision the scratch PDepend" >&2
    exit 1
  fi

  mkdir -p "${dir}"
  if ! docker run --rm -v "${dir}:/app" -w /app composer:2 \
    require "pdepend/pdepend:${version}" --no-interaction --no-progress -q >&2; then
    echo "ERROR: composer could not install pdepend/pdepend:${version}" >&2
    exit 1
  fi

  printf '{"ok":true,"scratch":"%s","version":"%s"}\n' "${dir}" "${version}"
}

# Emit code units for a request on stdin. The project and engine are mounted
# read-only; the driver parses, this function only routes.
cmd_units() {
  local request project
  request="$(cat)"

  project="$(printf '%s' "${request}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("project") or "")')"
  if [[ -z "${project}" || ! -d "${project}" ]]; then
    echo "ERROR: project directory not found: ${project}" >&2
    exit 1
  fi

  local resolved via root
  if ! resolved="$(_resolve_engine_root "${project}")"; then
    echo "ERROR: no PDepend engine found — add pdepend/pdepend to the project, or run: plugin.sh provision" >&2
    exit 1
  fi
  via="${resolved%%$'\t'*}"
  root="${resolved#*$'\t'}"

  local image
  image="$(_resolve_image "${project}")"
  if [[ -z "${image}" || "${image}" =~ [[:space:]] ]]; then
    echo "ERROR: invalid container image reference '${image}'" >&2
    exit 1
  fi

  local -a mounts=(-v "${project}:/app:ro" -v "${PLUGIN_DIR}:/plugin:ro")
  local autoload="/app/vendor/autoload.php"
  if [[ "${via}" == "scratch" ]]; then
    mounts+=(-v "${root}:/forensics-engine:ro")
    autoload="/forensics-engine/vendor/autoload.php"
  fi

  local payload
  payload="$(printf '%s' "${request}" | AUTOLOAD="${autoload}" python3 -c '
import json, os, sys
r = json.load(sys.stdin)
r["project"] = "/app"
r["autoload"] = os.environ["AUTOLOAD"]
print(json.dumps(r))')"

  printf '%s' "${payload}" | docker run --rm -i "${mounts[@]}" -w /app "${image}" \
    php -d display_errors=stderr /plugin/metrics.php
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
    echo "ERROR: php plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|units)" >&2
    exit 1
    ;;
esac
