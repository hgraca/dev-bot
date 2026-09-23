#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/install.sh
# Idempotent install for the refactor module.
#
# There is no OS package to install: the Rector phar is provisioned at runtime
# by the tool itself (pinned version + sha256). Install only prepares the shared
# phar cache directory and reports the runtime prerequisites (docker, bun).
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "refactor"

  # Shared, project-independent phar cache (keyed by Rector/PHP version at
  # runtime). Lives under the dev-bot storage dir, which is gitignored.
  local cache="${MODULE_DIR}/../../../storage/refactor/phars"
  if [[ -d "${cache}" ]]; then
    _skip "phar cache (${cache})"
  else
    mkdir -p "${cache}"
    _ok "phar cache created (${cache})"
  fi

  if command -v docker >/dev/null 2>&1; then
    _ok "docker found ($(docker --version 2>/dev/null | head -1 || echo installed))"
  else
    _warn "docker not found — the refactor tool needs it at runtime (PHP container runner)"
  fi

  _ok "refactor installed"
}

main "$@"
