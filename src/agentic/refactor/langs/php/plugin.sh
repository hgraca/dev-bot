#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/langs/php/plugin.sh
# PHP language plugin for the refactor tool.
#
# Subcommands:
#   meta    — plugin descriptor for the core's registry (lang, extensions, ops)
#   doctor  — report the resolved Rector engine, PHP version and container image
#   plan    — dry-run the requested refactor                        (T7)
#   apply   — perform the requested refactor                        (T7)
#
# Engine policy (ADR-4): the project's own `vendor/bin/rector` is preferred —
# right version, right vendor/autoload.php. A pinned scoped Composer install in
# the dev-bot scratch dir is the fallback. Never a phar: upstream abandoned that
# distribution because it broke on absolute paths and Docker mounts.
#
# Rector runs in the project's own PHP image when one can be detected, else the
# curated php:<version>-cli image. `--php-image` / REFACTOR_PHP_IMAGE override.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFACTOR_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
# Overridable for tests, and to relocate the scratch install.
STORAGE_DIR="${REFACTOR_STORAGE_DIR:-${REFACTOR_DIR}/../../../storage/refactor}"

OPS='["rename-method","rename-class","rename-static-method","rename-property"]'

# ── Engine resolution ─────────────────────────────────────────────────────────

# Rector version straight out of a composer.lock — deterministic, needs no PHP.
_rector_version_from_lock() {
  local lock="$1"
  [[ -f "${lock}" ]] || { echo "unknown"; return 0; }
  python3 - "${lock}" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown"); raise SystemExit
for pkg in data.get("packages", []) + data.get("packages-dev", []):
    if pkg.get("name") == "rector/rector":
        print(pkg.get("version", "unknown")); raise SystemExit
print("unknown")
PY
}

# The project's declared PHP version: .php-version wins, then composer.json.
_project_php_version() {
  local project="$1"
  if [[ -f "${project}/.php-version" ]]; then
    tr -d '[:space:]' < "${project}/.php-version"
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

# Resolve the engine. Echoes tab-separated: <via> <path> <version>.
# `via` is "project" or "scratch"; for scratch, <path> points into STORAGE_DIR.
_resolve_engine() {
  local project="$1"

  # 1. The project's own Rector.
  if [[ -x "${project}/vendor/bin/rector" ]]; then
    printf 'project\t%s\t%s\n' \
      "${project}/vendor/bin/rector" \
      "$(_rector_version_from_lock "${project}/composer.lock")"
    return 0
  fi

  # 2. A pinned scoped install in the scratch dir.
  local scratch=""
  if [[ -d "${STORAGE_DIR}/rector" ]]; then
    scratch="$(find "${STORAGE_DIR}/rector" -maxdepth 6 -type f \
      -path '*/vendor/bin/rector' 2>/dev/null | sort | head -1 || true)"
  fi
  if [[ -n "${scratch}" ]]; then
    local lock
    lock="$(dirname "$(dirname "$(dirname "${scratch}")")")/composer.lock"
    printf 'scratch\t%s\t%s\n' "${scratch}" "$(_rector_version_from_lock "${lock}")"
    return 0
  fi

  return 1
}

# ── Container runner ──────────────────────────────────────────────────────────

# The Rector rule class for an op.
_rule_for_op() {
  case "$1" in
    rename-method)        echo 'Rector\Renaming\Rector\MethodCall\RenameMethodRector' ;;
    rename-class)         echo 'Rector\Renaming\Rector\Name\RenameClassRector' ;;
    rename-static-method) echo 'Rector\Renaming\Rector\StaticCall\RenameStaticMethodRector' ;;
    rename-property)      echo 'Rector\Renaming\Rector\PropertyFetch\RenamePropertyRector' ;;
    *) return 1 ;;
  esac
}

# Resolve the PHP container image.
# Precedence: explicit > REFACTOR_PHP_IMAGE > the project's compose image >
# php:<php-version>-cli
_resolve_image() {
  local project="$1" explicit="${2:-}"

  if [[ -n "${explicit}" ]]; then echo "${explicit}"; return 0; fi
  if [[ -n "${REFACTOR_PHP_IMAGE:-}" ]]; then echo "${REFACTOR_PHP_IMAGE}"; return 0; fi

  local compose="" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${project}/${f}" ]]; then compose="${project}/${f}"; break; fi
  done
  if [[ -n "${compose}" ]]; then
    local img
    img="$(python3 - "${compose}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"^\s*image:\s*[\"']?([^\"'\s]+)", text, re.M)
print(m.group(1) if m else "")
PY
)"
    if [[ -n "${img}" ]]; then echo "${img}"; return 0; fi
  fi

  local ver
  ver="$(_project_php_version "${project}")"
  if [[ -n "${ver}" ]]; then echo "php:${ver}-cli"; else echo "php:cli"; fi
}

# Build the `docker run` argv for a Rector run and print it as a JSON array.
#
# args: <via> <project> <image> <config-host-path> <dry> <op> [paths...]
#
# The project is mounted at /app; a scratch engine is mounted at /refactor-engine.
# The generated config is mounted read-only at /refactor/rector.php. Since the
# config registers exactly one rule, `--only` is a belt-and-braces guarantee that
# nothing else in the run can change code.
_build_argv() {
  local via="$1" project="$2" image="$3" config="$4" dry="$5" op="$6"
  shift 6
  local rule
  rule="$(_rule_for_op "${op}")"

  local engine_host="${project}" engine_in_container="/app"
  if [[ "${via}" == "scratch" ]]; then
    engine_host="$(find "${STORAGE_DIR}/rector" -maxdepth 6 -type d -path '*/vendor/bin' 2>/dev/null | sort | head -1)"
    engine_host="$(dirname "${engine_host}")"
    engine_in_container="/refactor-engine"
  fi

  python3 - "${project}" "${image}" "${engine_host}" "${engine_in_container}" \
    "${config}" "${dry}" "${rule}" "$@" <<'PY'
import json, sys
project, image, engine_host, engine_in_container, config, dry, rule, *paths = sys.argv[1:]

argv = ["docker", "run", "--rm",
        "-v", f"{project}:/app",
        "-v", f"{config}:/refactor/rector.php:ro"]
if engine_in_container != "/app":
    argv += ["-v", f"{engine_host}:{engine_in_container}"]
argv += ["-w", "/app", image,
         "php", f"{engine_in_container}/vendor/bin/rector", "process",
         "--config", "/refactor/rector.php",
         "--only", rule.replace("\\\\", "\\"),
         "--clear-cache", "--no-progress-bar", "--output-format=json"]
if dry == "true":
    argv.append("--dry-run")
argv += paths
print(json.dumps(argv))
PY
}

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_meta() {
  printf '{"lang":"php","extensions":[".php"],"ops":%s}\n' "${OPS}"
}

cmd_doctor() {
  local project="${PWD}" image="" want_command="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --image)   image="$2"; shift 2 ;;
      --command) want_command="true"; shift ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    printf '{"ok":false,"error":"project directory not found: %s"}\n' "${project}"
    exit 1
  fi

  local resolved_image
  resolved_image="$(_resolve_image "${project}" "${image}")"

  local engine
  if ! engine="$(_resolve_engine "${project}")"; then
    python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
project, image = sys.argv[1:3]
print(json.dumps({
    "ok": False,
    "lang": "php",
    "project": project,
    "image": image,
    "error": "no Rector engine found",
    "hint": "add rector/rector to the project, or provision the scratch install",
}))
PY
    exit 1
  fi

  local via path version
  IFS=$'\t' read -r via path version <<<"${engine}"

  local command=""
  if [[ "${want_command}" == "true" ]]; then
    command="$(_build_argv "${via}" "${project}" "${resolved_image}" \
      "/tmp/rector.php" "true" "rename-method")"
  fi

  python3 - "${project}" "${via}" "${path}" "${version}" \
    "$(_project_php_version "${project}")" "${resolved_image}" "${command}" <<'PY'
import json, sys
project, via, path, version, php_version, image, command = sys.argv[1:8]
out = {
    "ok": True,
    "lang": "php",
    "project": project,
    "php_version": php_version or None,
    "image": image,
    "engine": {"via": via, "path": path, "version": version},
}
if command:
    out["command"] = json.loads(command)
print(json.dumps(out))
PY
}

# Provision a pinned, scoped Rector into the scratch dir. Composer is the official
# distribution channel — there is no official phar.
cmd_provision() {
  local version="${1:-^2.6}"
  local dir="${STORAGE_DIR}/rector"

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required to provision the scratch Rector" >&2
    exit 1
  fi

  mkdir -p "${dir}"
  if ! docker run --rm -v "${dir}:/app" -w /app composer:2 \
    require "rector/rector:${version}" --no-interaction --no-progress -q >&2; then
    echo "ERROR: composer could not install rector/rector:${version}" >&2
    exit 1
  fi

  printf '{"ok":true,"scratch":"%s","version":"%s"}\n' "${dir}" "${version}"
}

case "${1:-}" in
  meta)      cmd_meta ;;
  doctor)    shift; cmd_doctor "$@" ;;
  provision) shift; cmd_provision "$@" ;;
  *)
    echo "ERROR: php plugin: unsupported subcommand '${1:-}' (expected meta|doctor|plan|apply)" >&2
    exit 1
    ;;
esac
