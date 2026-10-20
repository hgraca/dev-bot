#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/lsp/intelephense.sh
# Launch the Intelephense PHP language server for opencode.
#
# opencode's built-in PHP server resolves the intelephense binary itself, but the
# lsp override that delivers files.exclude (via LSP workspace/configuration) must
# re-declare the launch command — and intelephense is not on PATH. This wrapper
# prefers the copy devbot pins (a newer release with upstream memory-leak fixes)
# and falls back to the one opencode installs.
#
# Usage: intelephense.sh --stdio
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"

# Cap each server's V8 heap so a run-away index can swap out the machine
# (a single instance has been seen holding ~3.3 GB of swap while indexing).
# Append AFTER inherited options: Node uses the LAST occurrence, so prepending
# would let an inherited --max-old-space-size override the cap.
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=2048"

# Honour the XDG base-dir overrides — opencode resolves its bin under
# ${XDG_DATA_HOME:-~/.local/share}/opencode/bin.
_data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
_cache_home="${XDG_CACHE_HOME:-${HOME}/.cache}"

for _bin in \
  "${DEV_BOT_ROOT}/storage/intelephense/node_modules/.bin/intelephense" \
  "${_data_home}/opencode/bin/node_modules/.bin/intelephense" \
  "${_cache_home}/opencode/node_modules/.bin/intelephense" \
  "${_cache_home}/opencode/bin/node_modules/.bin/intelephense"; do
  if [[ -x "${_bin}" ]]; then
    exec "${_bin}" "$@"
  fi
done

if _bin="$(command -v intelephense 2>/dev/null)"; then
  exec "${_bin}" "$@"
fi

echo "FATAL: intelephense not found — open opencode once to install it, or install it globally" >&2
exit 1
