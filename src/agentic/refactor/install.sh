#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/install.sh
# Idempotent install for the refactor module.
#
# There is no OS package to install: Rector is provisioned at runtime by the
# plugin (a pinned scoped Composer install, or the project's own copy). Install
# only prepares the shared engine cache directory and reports the runtime
# prerequisites (docker, python3).
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "refactor"

  # Shared, project-independent engine caches. Live under the dev-bot storage
  # dir, which is gitignored. The engines themselves are provisioned on demand
  # (each language plugin's `provision`), not at install time.
  local cache
  for cache in "${MODULE_DIR}/../../../storage/refactor/rector" \
    "${MODULE_DIR}/../../../storage/refactor/ts" \
    "${MODULE_DIR}/../../../storage/refactor/py"; do
    if [[ -d "${cache}" ]]; then
      _skip "engine cache (${cache})"
    else
      mkdir -p "${cache}"
      _ok "engine cache created (${cache})"
    fi
  done

  if command -v docker >/dev/null 2>&1; then
    _ok "docker found ($(docker --version 2>/dev/null | head -1 || echo installed))"
  else
    _warn "docker not found — the refactor tool needs it at runtime (container runner)"
  fi

  _ok "refactor installed"
}

main "$@"
