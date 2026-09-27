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

# A PHP image from a compose file, or "" when none is confidently the runtime.
# Picking the first `image:` is wrong for the common db/app/service layout, so
# prefer a service named like the PHP app, then an obviously-PHP image, then a
# locally-built service's image.
_compose_php_image() {
  python3 - "$1" <<'PY'
import re, sys

lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
services = {}
current = None
in_services = False
for line in lines:
    if re.match(r"^services:\s*$", line):
        in_services = True
        continue
    if in_services and re.match(r"^\S", line):
        in_services = False
        continue
    if not in_services:
        continue
    named = re.match(r"^\s{2}([A-Za-z0-9_.-]+):\s*$", line)
    if named:
        current = named.group(1)
        services.setdefault(current, {"image": "", "build": False})
        continue
    if current is None:
        continue
    image = re.match(r"^\s+image:\s*[\"']?([^\"'\s]+)", line)
    if image:
        services[current]["image"] = image.group(1)
    if re.match(r"^\s+build:", line):
        services[current]["build"] = True

phpish = {"php", "php-fpm", "fpm", "app", "api", "web", "www", "application"}
for name, svc in services.items():
    if name.lower() in phpish and svc["image"]:
        print(svc["image"]); raise SystemExit
for svc in services.values():
    if re.match(r"^(?:.*/)?php(?::|-)", svc["image"] or ""):
        print(svc["image"]); raise SystemExit
for svc in services.values():
    if svc["build"] and svc["image"]:
        print(svc["image"]); raise SystemExit
print("")
PY
}

# Precedence: explicit > FORENSICS_PHP_IMAGE > scratch engine PHP > project
# compose image > php:<project-version>-cli
#
# $3 is the scratch engine root. A scratch engine is built by composer:2's PHP,
# so it must run on an image at least that new — the project's own (possibly much
# older) PHP would fail its platform check.
_resolve_image() {
  local project="$1" explicit="${2:-}" engine_root="${3:-}"
  if [[ -n "${explicit}" ]]; then
    echo "${explicit}"
    return 0
  fi
  if [[ -n "${FORENSICS_PHP_IMAGE:-}" ]]; then
    echo "${FORENSICS_PHP_IMAGE}"
    return 0
  fi

  if [[ -n "${engine_root}" && -f "${engine_root}/.php-version" ]]; then
    local engine_php
    engine_php="$(tr -d '[:space:]' <"${engine_root}/.php-version")"
    if [[ -n "${engine_php}" ]]; then
      echo "php:${engine_php}-cli"
      return 0
    fi
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
    image="$(_compose_php_image "${compose}")"
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
print(json.dumps({"ok": False, "lang": "php", "error": "project directory not found: %s" % sys.argv[1]}))
PY
    exit 1
  fi

  local resolved via root
  if ! resolved="$(_resolve_engine_root "${project}")"; then
    python3 - "${project}" <<'PY'
import json, sys
print(json.dumps({"ok": False, "lang": "php", "project": sys.argv[1], "error": "no PDepend engine found", "hint": "add pdepend/pdepend to the project, or run: plugin.sh provision"}))
PY
    exit 1
  fi
  via="${resolved%%$'\t'*}"
  root="${resolved#*$'\t'}"

  local version
  version="$(_pdepend_version_from_lock "${root}/composer.lock")"
  if [[ -z "${version}" || "${version}" == "unknown" ]]; then
    version="$(_pdepend_version_from_lock "${project}/composer.lock")"
  fi
  local engine_image=""
  [[ "${via}" == "scratch" ]] && engine_image="${root}"
  python3 - "${project}" "$(_resolve_image "${project}" "${image}" "${engine_image}")" "${via}" "${root}" "${version}" <<'PY'
import json, sys
project, image, via, root, version = sys.argv[1:6]
print(json.dumps({"ok": True, "lang": "php", "project": project, "image": image,
                  "engine": {"via": via, "path": root, "version": version}}))
PY
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

  # Record the PHP the engine was built for, so it is always run on a compatible
  # image regardless of the analysed project's own PHP version.
  docker run --rm composer:2 php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;' \
    >"${dir}/.php-version" 2>/dev/null || true

  python3 - "${dir}" "${version}" "$(tr -d '[:space:]' <"${dir}/.php-version" 2>/dev/null || echo "")" <<'PY'
import json, sys
print(json.dumps({"ok": True, "scratch": sys.argv[1], "version": sys.argv[2], "php": sys.argv[3]}))
PY
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
  local engine_image=""
  [[ "${via}" == "scratch" ]] && engine_image="${root}"
  image="$(_resolve_image "${project}" "" "${engine_image}")"
  if [[ -z "${image}" || "${image}" =~ [[:space:]] || "${image}" == -* ]]; then
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

  # The analysed repository's own autoloader runs inside this container, so it
  # gets no network, no root and a read-only rootfs: the analysis needs none.
  printf '%s' "${payload}" | docker run --rm -i \
    --network none --read-only --tmpfs /tmp -e HOME=/tmp \
    --user "$(id -u):$(id -g)" \
    "${mounts[@]}" -w /app "${image}" \
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
