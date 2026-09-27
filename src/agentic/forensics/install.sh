#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/install.sh
# Idempotent install for the forensics module.
#
# There is no OS package to install: each language engine is provisioned on
# demand by its plugin's `provision` (a pinned scratch install under
# storage/forensics/<lang>, which is gitignored). Install only prepares those
# shared caches and reports the runtime prerequisites.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "forensics"

  local cache
  for cache in "${MODULE_DIR}/../../../storage/forensics/php" \
    "${MODULE_DIR}/../../../storage/forensics/py" \
    "${MODULE_DIR}/../../../storage/forensics/ts"; do
    if [[ -d "${cache}" ]]; then
      _skip "engine cache (${cache})"
    else
      mkdir -p "${cache}"
      _ok "engine cache created (${cache})"
    fi
  done

  _ok "forensics installed"
}

main "$@"
