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

# qmd query (auto-expand + rerank) needs qmd's own generation + reranking
# GGUF models in its model cache (`qmd pull`); without them the LLM call hangs
# until the MCP timeout (-32001). The Dockerfile bakes them; this guard covers
# older images. Non-fatal — `qmd search` / `rerank:false` still work without.
if qmd doctor 2>/dev/null | grep -q "missing 0/3"; then
  echo "qmd models already present"
else
  echo "pulling qmd models (embedding + query-expansion + reranker)..."
  if timeout "${QMD_PULL_TIMEOUT:-600}" qmd pull >/dev/null 2>&1; then
    echo "qmd models ready"
  else
    echo "WARN: qmd pull failed or timed out — 'qmd query' rerank will be unavailable (search still works)"
  fi
fi
