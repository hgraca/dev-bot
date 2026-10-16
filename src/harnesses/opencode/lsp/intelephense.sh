#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/lsp/intelephense.sh
# Launch the Intelephense PHP language server for opencode.
#
# opencode's built-in PHP server resolves the intelephense binary itself, but the
# lsp override that delivers intelephense.files.exclude (via LSP
# workspace/configuration) must re-declare the launch command — and intelephense
# is not on PATH. This wrapper resolves the copy opencode installs under its
# global bin dir and execs it.
#
# Usage: intelephense.sh --stdio
# =============================================================================

set -euo pipefail

for _bin in \
  "${HOME}/.local/share/opencode/bin/node_modules/.bin/intelephense" \
  "${HOME}/.cache/opencode/bin/node_modules/.bin/intelephense"; do
  if [[ -x "${_bin}" ]]; then
    exec "${_bin}" "$@"
  fi
done

if _bin="$(command -v intelephense 2>/dev/null)"; then
  exec "${_bin}" "$@"
fi

echo "FATAL: intelephense not found — open opencode once to install it, or install it globally" >&2
exit 1
