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
BYTE_IDEM_FAIL=0
for f in "${BYTE_IDEM_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    if ! cmp -s "${BYTE_IDEM_SNAP}/${f}" "$f"; then
      echo "BYTE-IDEMPOTENCY-FAIL: $f changed on second reinit"
      BYTE_IDEM_FAIL=1
    fi
  fi
done
rm -r "${BYTE_IDEM_SNAP}" 2>/dev/null || true
if [[ ${BYTE_IDEM_FAIL} -eq 0 ]]; then
  echo "BYTE-IDEMPOTENCY-PASS: second reinit left all generated files unchanged"
else
  echo "BYTE-IDEMPOTENCY-FAIL: second reinit changed generated files — reinit is not byte-idempotent"
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

# qmd query (auto-expand + rerank) needs qmd's own generation + reranking
# GGUF models in its model cache (`qmd pull`); without them the LLM call hangs
# until the MCP timeout (-32001). The Dockerfile bakes them; this guard covers
# older images. Non-fatal — `qmd search` / `rerank:false` still work without.
#
# Serialized with the SAME cross-process llama lock qmd/init.sh uses
# (XDG_CACHE_HOME/qmd/.llama.lock — a host mount shared by cc + oc containers):
# `qmd doctor` runs a llama CPU probe (~14 s) and `qmd pull` writes the shared
# model cache; running either from two containers at once doubles the CPU burn
# and races the same model files. Bounded wait (60 s); if the sibling is still
# holding the lock, skip the guard this run (models are likely being handled
# there) rather than block.
_acquire_llama_guard_lock() {
  local lock="${XDG_CACHE_HOME:-$HOME/.cache}/qmd/.llama.lock"
  mkdir -p "$(dirname "${lock}")" 2>/dev/null || return 1
  exec 200>"${lock}" 2>/dev/null || return 1
  local waited=0
  while ! { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; }; do
    waited=$((waited + 2))
    if (( waited >= 60 )); then return 1; fi
    sleep 2
  done
  return 0
}

if _acquire_llama_guard_lock; then
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
  exec 200>&- 2>/dev/null || true
else
  echo "WARN: qmd llama lock busy (sibling container) — skipping model check/pull; 'qmd query' rerank may be unavailable this run"
fi
