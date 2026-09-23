#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/langs/php/plugin.sh
# PHP language plugin for the refactor tool.
#
# Subcommands:
#   meta    — plugin descriptor for the core's registry (lang, extensions, ops)
#   doctor  — report the resolved Rector engine + the project's PHP version
#   plan    — dry-run the requested refactor                        (T7)
#   apply   — perform the requested refactor                        (T7)
#
# Engine policy (ADR-4): the project's own `vendor/bin/rector` is preferred —
# right version, right vendor/autoload.php. A pinned scoped Composer install in
# the dev-bot scratch dir is the fallback. Never a phar: upstream abandoned that
# distribution because it broke on absolute paths and Docker mounts.
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
    scratch="$(find "${STORAGE_DIR}/rector" -maxdepth 3 -type f \
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

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_meta() {
  printf '{"lang":"php","extensions":[".php"],"ops":%s}\n' "${OPS}"
}

cmd_doctor() {
  local project="${PWD}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    printf '{"ok":false,"error":"project directory not found: %s"}\n' "${project}"
    exit 1
  fi

  local engine
  if ! engine="$(_resolve_engine "${project}")"; then
    printf '{"ok":false,"error":"no Rector engine found","hint":"add rector/rector to the project, or run the scratch install"}\n'
    exit 1
  fi

  local via path version
  IFS=$'\t' read -r via path version <<<"${engine}"
  python3 - "${project}" "${via}" "${path}" "${version}" "$(_project_php_version "${project}")" <<'PY'
import json, sys
project, via, path, version, php_version = sys.argv[1:6]
print(json.dumps({
    "ok": True,
    "lang": "php",
    "project": project,
    "php_version": php_version or None,
    "engine": {"via": via, "path": path, "version": version},
}))
PY
}

case "${1:-}" in
  meta)   cmd_meta ;;
  doctor) shift; cmd_doctor "$@" ;;
  *)
    echo "ERROR: php plugin: unsupported subcommand '${1:-}' (expected meta|doctor|plan|apply)" >&2
    exit 1
    ;;
esac
