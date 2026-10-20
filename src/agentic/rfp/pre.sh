#!/usr/bin/env bash
# =============================================================================
# src/agentic/rfp/pre.sh
# Prerequisites check for the rfp module.
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# Idempotent — safe to re-run at any time.
#
# Hard requirement: python3, used by the questionnaire extraction recipes and
# the shared lifecycle helpers. pdftotext is provisioned by install.sh (poppler)
# and checked here; pandoc is an optional HTML fallback.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "rfp — prerequisites"

  if command -v python3 >/dev/null 2>&1; then
    _ok "python3 found: $(python3 --version 2>&1)"
  else
    _fatal "python3 not found — the rfp skill's questionnaire extractors require it: https://www.python.org/"
    exit 1
  fi

  if command -v pdftotext >/dev/null 2>&1; then
    _ok "pdftotext found"
  else
    _warn "pdftotext not found — install.sh installs poppler; PDF questionnaires need it"
  fi

  if command -v pandoc >/dev/null 2>&1; then
    _ok "pandoc found (optional HTML fallback)"
  else
    _skip "pandoc not found — optional HTML fallback"
  fi

  if command -v bats >/dev/null 2>&1; then
    _ok "bats found: $(bats --version 2>/dev/null || echo 'present')"
  else
    _skip "bats not found — only needed to run this module's tests"
  fi

  _ok "rfp prerequisites check complete"
}

main "$@"
