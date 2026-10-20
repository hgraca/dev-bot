#!/usr/bin/env bash
# =============================================================================
# src/agentic/rfp/install.sh
# Installs the rfp module's only external dependency: poppler's pdftotext, used
# for PDF questionnaires. The command and skill are plain markdown, and the
# other extractors use python3's standard library.
#
# Idempotent — skips when pdftotext is already present.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "rfp"

  if ! command -v python3 >/dev/null 2>&1; then
    _error "python3 not found — required by the questionnaire extractors."
    exit 1
  fi
  _ok "python3 present ($(python3 --version 2>&1))"

  if command -v pdftotext >/dev/null 2>&1; then
    _ok "pdftotext present"
  else
    _info "pdftotext missing — installing poppler for PDF extraction..."
    case "$(uname -s)" in
      Darwin)
        if command -v brew >/dev/null 2>&1; then
          brew install poppler
          _ok "poppler installed"
        else
          _warn "Homebrew not found — install poppler manually for PDF questionnaires"
        fi
        ;;
      Linux)
        if command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y poppler-utils
          _ok "poppler-utils installed"
        elif command -v apt-get >/dev/null 2>&1; then
          sudo apt-get install -y poppler-utils
          _ok "poppler-utils installed"
        else
          _warn "No supported package manager found (dnf, apt-get) — install poppler-utils manually"
        fi
        ;;
      *)
        _warn "Unsupported OS: $(uname -s) — install poppler manually for PDF questionnaires"
        ;;
    esac
  fi

  _ok "rfp ready — command /rfp and skill devbot:rfp"
}

main "$@"
