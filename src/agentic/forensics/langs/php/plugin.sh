#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/langs/php/plugin.sh
# PHP language plugin for the forensics tool.
#
# Subcommands:
#   meta     — plugin descriptor for the core's registry
#   doctor   — report the resolved PDepend engine
#   provision— install a pinned PDepend into the shared scratch dir
#   units    — emit code units + complexity                       (T0.5)
#
# Engine policy: the project's own `vendor/bin/pdepend` is preferred (right
# version, right autoloader). A pinned Composer install in the shared scratch dir
# is the fallback. Running the engine (units) inside the project's PHP image is T0.5.
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

# Echoes tab-separated: <via> <path> <version>, or returns 1 when unresolved.
_resolve_engine() {
  local project="$1"
  if [[ -x "${project}/vendor/bin/pdepend" ]]; then
    printf 'project\t%s\t%s\n' "${project}/vendor/bin/pdepend" "$(_pdepend_version_from_lock "${project}/composer.lock")"
    return 0
  fi
  if [[ -x "${STORAGE_DIR}/php/vendor/bin/pdepend" ]]; then
    printf 'scratch\t%s\t%s\n' "${STORAGE_DIR}/php/vendor/bin/pdepend" "$(_pdepend_version_from_lock "${STORAGE_DIR}/php/composer.lock")"
    return 0
  fi
  return 1
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

  local engine
  if ! engine="$(_resolve_engine "${project}")"; then
    printf '{"ok":false,"lang":"php","project":"%s","error":"no PDepend engine found","hint":"add pdepend/pdepend to the project, or run: plugin.sh provision"}\n' "${project}"
    exit 1
  fi

  local via path version
  IFS=$'\t' read -r via path version <<<"${engine}"
  printf '{"ok":true,"lang":"php","project":"%s","engine":{"via":"%s","path":"%s","version":"%s"}}\n' \
    "${project}" "${via}" "${path}" "${version}"
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

cmd_run() {
  echo "ERROR: php units are not implemented yet (Phase 0, task T0.5)" >&2
  exit 3
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
    cmd_run "$@"
    ;;
  *)
    echo "ERROR: php plugin: unsupported subcommand '${1:-}' (expected meta|doctor|provision|units)" >&2
    exit 1
    ;;
esac
