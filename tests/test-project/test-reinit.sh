# shellcheck shell=bash
# Runs as the host uid (Pattern A image) — put ~/.local/bin on PATH first so
# the devbot link is found. npm's global prefix also points at ~/.local so
# `npm install -g` (used by the qmd installer) works as this non-root user.
export PATH="$HOME/.local/bin:$PATH"
npm config set prefix "$HOME/.local" 2>/dev/null || true

# If devbot is not installed, install it with the documented install line
# (docs homepage hero). The branch to install comes from the launcher
# (DEV_BOT_TEST_BRANCH, default main) — e.g. `./test-oc.sh my-branch`.
BRANCH="${DEV_BOT_TEST_BRANCH:-main}"
if ! command -v devbot >/dev/null 2>&1; then
  echo "devbot not found — installing (branch: ${BRANCH})..."
  curl -fsSL "https://raw.githubusercontent.com/hgraca/dev-bot/${BRANCH}/install.sh" | bash -s -- --org hgraca --branch "${BRANCH}"
fi

# Host ollama (reachable in-container via --network host at localhost:18434) is
# required only when the installed dev-bot selects the codebase-index engine —
# the shipped default (codebase-memory + mdctx) needs none. Gate on the
# effective provider now, before reinit wires the engine. See
# require_host_ollama_for_codebase_engine in test-lib.sh.
# shellcheck source=./test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"
require_host_ollama_for_codebase_engine "${DEV_BOT_INSTALL_DIR:-$HOME/.local/share/dev-bot}"

echo
echo "removing old files..."
rm \
  -rf \
  .agents/agents \
  .agents/commands \
  .agents/skills \
  .agents/tools \
  .agents/logs \
  graphify-out \
  .graphifyignore \
  .playwright-mcp \
  AGENTS.md \
  .opencode \
  .codex \
  .cursor \
  .claude \
  .mcp.json \
  AGENTS.md \
  CLAUDE.md \
  opencode.jsonc \
  repomix.config.json
#   \
#  ~/.agents
#  graphify-out \
#  .devbot.project.jsonc \

echo
echo "running 'devbot reinit'..."
echo
devbot reinit
echo

# ── Byte-idempotency probe (audit-32 NOTE, fixed in audit-33) ────────────────
# `devbot reinit` must be byte-idempotent: re-running it on an already-
# initialized project must not change any generated file. Known drift causes
# (all fixed): remove_mcp_key.py's whole-file json.dump rewrite (expanded
# layout + dropped comments), the graphify AGENTS.md section-removal leaving a
# trailing blank, and reset.sh churning MCP keys that already match their
# module templates (reordering the mcp map). Snapshot after reinit #1, reinit
# a second time, and byte-compare the generated files.
BYTE_IDEM_FILES=(
  ".devbot.project.jsonc"
  "AGENTS.md"
  "CLAUDE.md"
  "opencode.jsonc"
  ".mcp.json"
)
echo
echo "running second 'devbot reinit' (byte-idempotency probe)..."
echo
BYTE_IDEM_SNAP="$(mktemp -d)"
for f in "${BYTE_IDEM_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$(dirname "${BYTE_IDEM_SNAP}/${f}")"
    cp "$f" "${BYTE_IDEM_SNAP}/${f}"
  fi
done
devbot reinit
# Record the captured evidence for the in-session audit (§1): per-file SHA-256
# byte values + the verdict. This runs BEFORE the harness starts, so start.sh
# rotates the log into .agents/logs/rotated/ and the audit reports PASS/FAIL
# from captured evidence instead of NOT-RUN. A FAIL never aborts provisioning.
BYTE_IDEM_LOG=".agents/logs/byte-idempotency.log"
mkdir -p "$(dirname "${BYTE_IDEM_LOG}")"
BYTE_IDEM_FAIL=0
byte_idempotency_report "${BYTE_IDEM_SNAP}" "." "${BYTE_IDEM_LOG}" \
  "${BYTE_IDEM_FILES[@]}" || BYTE_IDEM_FAIL=$?
rm -r "${BYTE_IDEM_SNAP}" 2>/dev/null || true
if (( BYTE_IDEM_FAIL != 0 )); then
  echo "  (byte-idempotency evidence: ${BYTE_IDEM_LOG})" >&2
fi
echo

# Grant the dev-bot install dir through opencode's external_directory
# permission: the agent must read/write the install (skills, agents, hooks,
# tools) while auditing. Merges into the existing map (idempotent, JSONC
# preserved); no-ops if opencode.jsonc / the block is absent (claudecode-only
# flows).
_DEV_BOT_INSTALL="${DEV_BOT_INSTALL_DIR:-$HOME/.local/share/dev-bot}"
python3 "${_DEV_BOT_INSTALL}/src/_shared/upsert_opencode_permission.py" \
  "${PWD}/opencode.jsonc" "${_DEV_BOT_INSTALL}/**" 2>/dev/null || true

# Pre-seed the opencode-codebase-index plugin cache to a COMPLETE state
# (including native/*.node) before opencode ever loads it. opencode's runtime
# fetch extracts the package progressively, and the plugin resolves its native
# binding once at load — loading mid-extraction silently degrades it to the
# mock binding (no parsing / indexing) for the whole session. opencode reuses
# a complete cache, so this is a no-op when the Dockerfile bake already seeded
# it. Belt-and-braces for containers whose image predates the bake.
CBI_CACHE="$HOME/.cache/opencode/packages/opencode-codebase-index@latest"
if [ ! -d "$CBI_CACHE/node_modules/opencode-codebase-index/native" ]; then
  mkdir -p "$CBI_CACHE"
  npm install --no-save --no-audit --no-fund --prefix "$CBI_CACHE" opencode-codebase-index@0.25.1 >/dev/null
fi

# qmd is BM25-only — no model download, no embeddings (ADR
# 20260913072905-qmd-bm25-only-no-model-downloads). Nothing to pull or warm.
