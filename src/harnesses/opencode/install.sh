#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/install.sh
# Provision the Intelephense PHP language server devbot prefers for opencode.
#
# opencode bundles an older Intelephense (1.16.5); the LSP wrapper
# (lsp/intelephense.sh) prefers the copy installed here so a newer release's
# memory fixes apply. Version is pinned in versions.env.
#
# Idempotent — skips when the pinned version is already present.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

PREFIX="${DEV_BOT_ROOT}/storage/intelephense"
PKG_JSON="${PREFIX}/node_modules/intelephense/package.json"

_header_3 "Intelephense (opencode LSP)"

if [[ -f "${PKG_JSON}" ]]; then
  _installed="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${PKG_JSON}" 2>/dev/null || true)"
  if [[ "${_installed}" == "${INTELEPHENSE_VERSION}" ]]; then
    _skip "intelephense@${INTELEPHENSE_VERSION} already present"
    exit 0
  fi
fi

if ! command -v npm >/dev/null 2>&1; then
  _warn "npm not found — cannot provision intelephense@${INTELEPHENSE_VERSION}"
  exit 0
fi

_log "Installing intelephense@${INTELEPHENSE_VERSION} into storage/intelephense"
if ! npm install --silent --prefix "${PREFIX}" "intelephense@${INTELEPHENSE_VERSION}" >/dev/null 2>&1; then
  _warn "npm install intelephense@${INTELEPHENSE_VERSION} failed — the LSP falls back to opencode's copy"
  exit 0
fi

_log "intelephense@${INTELEPHENSE_VERSION} ready"
