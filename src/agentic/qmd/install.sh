#!/usr/bin/env bash
# Install QMD (Quick Markdown search) CLI via npm.
# Installs the @tobilu/qmd npm package globally.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# GATE: Requires npm (Node.js package manager).

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "qmd"

  # ── Dependency check: npm ────────────────────────────────────────────────
  if ! command -v npm >/dev/null 2>&1; then
    _fatal "npm is required but not installed."
    echo "  Install Node.js via your system package manager (apt, dnf, brew) or nvm." >&2
    exit 1
  fi

  # ── Install/verify QMD ───────────────────────────────────────────────────
  if ! command -v qmd >/dev/null 2>&1; then
    _info "Installing @tobilu/qmd via npm..."
    local attempt=1
    while ! npm install -g @tobilu/qmd >/dev/null 2>&1; do
      if [[ ${attempt} -ge 3 ]]; then
        _warn "npm install @tobilu/qmd failed after ${attempt} attempts (check network) — qmd unavailable"
        return 1
      fi
      _warn "npm install @tobilu/qmd failed (attempt ${attempt}/3) — retrying in 3s..."
      sleep 3
      attempt=$((attempt + 1))
    done
    _ok "QMD installed: $(qmd --version 2>/dev/null || true)"
  else
    _skip "QMD ($(qmd --version 2>/dev/null || echo 'installed'))"
  fi

  # ── Ensure qmd models (independent process, non-blocking) ────────────────
  # qmd query (auto-expand + rerank) needs qmd's own llama models (embedding +
  # query-expansion + reranker). qmd pull skips models already in the cache
  # ("cached/checked"); run it detached so a first-time (~2 GB) download never
  # blocks the install. Models become available once the background pull ends.
  # Presence check is a fast file glob — NOT `qmd doctor` (its device probe
  # runs the llama backend and takes ~14 s on CPU).
  if compgen -G "${QMD_MODELS_DIR:-$HOME/.cache/qmd/models}/*.gguf" >/dev/null 2>&1; then
    _skip "qmd models already cached"
  else
    _info "qmd models not cached — pulling in the background (qmd pull)"
    ( nohup qmd pull >/dev/null 2>&1 & ) || true
  fi
}

main
