#!/usr/bin/env bash
# =============================================================================
# src/agentic/mdctx/init.sh
# Set up mdctx for a project: build the project's markdown-memory index.
#
# mdctx is a zero-ML-dependency keyword index (RAKE + BM25) over a directory of
# markdown files. This init script:
#   1. Checks the mdctx CLI is installed
#   2. Builds an incremental index over <devbot-dir>/memory/latent, written to
#      <project>/.mdctx/context-index.json (explicit -o — the index must never
#      pollute the latent tree it indexes)
#   3. Excludes the project's .mdctx/ dir from git (.git/info/exclude) so the
#      generated index JSON is never committed
#
# The shared global store (DEV_BOT_ROOT/storage/global-memories) is indexed by
# the memory module's init.sh (it owns that store); this script covers only the
# per-project latent vault. mdctx does not follow symlinks, so the
# latent/global symlink is NOT covered here — hence the separate global index.
#
# Usage:
#   init.sh                         # init in current directory
#   init.sh /path/to/project        # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── Resolve paths ─────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

_header_3 "mdctx init — $(basename "${PROJECT_DIR}")"

if ! command -v mdctx >/dev/null 2>&1; then
  _warn "mdctx CLI not found — run install.sh first"
  exit 1
fi

_ok "mdctx CLI: $(mdctx --version 2>/dev/null || echo 'installed')"

# ── Check vault exists ────────────────────────────────────────────────────────

DEVBOT_DIR="$(_devbot_get_project_dir "${PROJECT_DIR}")"
LATENT_DIR="${PROJECT_DIR}/${DEVBOT_DIR}/memory/latent"

if [[ ! -d "${LATENT_DIR}" ]]; then
  _warn "No latent memory directory found at:"
  echo "    ${LATENT_DIR}"
  echo "  Create it or ensure your project has the <devbot-dir>/memory/latent/ structure."
  echo "  Skipping the project mdctx index (the global store is indexed by the memory module)."
  exit 0
fi
_ok "Latent directory: ${LATENT_DIR}"

# ── Build project index ───────────────────────────────────────────────────────

INDEX_DIR="${PROJECT_DIR}/.mdctx"
INDEX_FILE="${INDEX_DIR}/context-index.json"

mkdir -p "${INDEX_DIR}"

_header_3 "Building mdctx project index"

# Incremental + hash-cached: unchanged files are skipped, so re-runs are cheap
# and byte-stable (no spurious diffs). Never run `mdctx init` here — it
# installs git hooks + a CI workflow into the project (devbot policy: our
# manifests/lifecycle own registration, not the engine's auto-config).
if mdctx build "${LATENT_DIR}" -o "${INDEX_FILE}" 2>&1 | sed 's/^/  /'; then
  _ok "mdctx project index written: ${INDEX_FILE}"
else
  _error "mdctx build failed — check mdctx is installed (install.sh) and the latent dir is readable."
  exit 1
fi

# ── Exclude .mdctx from git ───────────────────────────────────────────────────

# The index JSON is a generated artifact — exclude it from the repo via the
# local (non-committed) .git/info/exclude, same pattern as the memory module's
# vault exclusion. Only meaningful when the project is a git repo.
if [[ -d "${PROJECT_DIR}/.git" ]]; then
  if _upsert_gitignore_section "${PROJECT_DIR}/.git/info/exclude" \
    "# >>> DEVBOT - mdctx" \
    "# <<< DEVBOT - mdctx" \
    ".mdctx"
  then
    _ok ".git/info/exclude updated (.mdctx)"
  else
    _skip ".git/info/exclude upsert failed"
  fi
fi

_ok "mdctx init complete for $(basename "${PROJECT_DIR}")"
