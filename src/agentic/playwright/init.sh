#!/usr/bin/env bash
# =============================================================================
# src/agentic/playwright/init.sh
# Symlink the EPIPE-swallowing MCP wrapper into the project harness dirs so
# the .mcp.json / opencode.jsonc launch commands can reach it.
#
# Mirrors graphify/init.sh's symlink pattern. Agentic init runs BEFORE the
# harness inits (bin/init.sh: tools -> agentic -> harnesses), so the harness
# dirs are created here rather than assumed to exist.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh" 2>/dev/null || true

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

_header_3 "Playwright MCP Init"

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Check if harnesses are disabled ──────────────────────────────────────────

# The EPIPE-swallowing wrapper is shared (src/_shared/mcp-stdio-wrapper.js) —
# chrome-devtools and codebase-index symlink the same file under their own names.

  # The harness links this module's declared MCP assets (mcp.json "assets").
# ── Migrate a pre-mount launch command in an existing config ─────────────────
# MCP registration is insert-only (merge_mcp_jsonc.py SKIP_EXISTS), so a project
# initialised before the container bind mount would keep the broken command
# forever: file upload and filename screenshots fail without it. Rewrite the two
# known fragments in place; both harness shapes carry the same command text.
_migrate_launch_commands() {
  local config out changed=0
  for config in "${PROJECT_DIR}/opencode.jsonc" "${PROJECT_DIR}/.mcp.json"; do
    [[ -f "${config}" ]] || continue
    grep -qF 'docker run --rm -i --label dev-bot.mcp=playwright mcp/playwright' "${config}" 2>/dev/null \
      || grep -qF -- '--browser chromium 2>>.agents/logs/playwright-mcp.log' "${config}" 2>/dev/null \
      || continue
    out="$(CONFIG="${config}" python3 - <<'PY'
import os

p = os.environ["CONFIG"]
with open(p) as fh:
    before = fh.read()

after = before.replace(
    "docker run --rm -i --label dev-bot.mcp=playwright mcp/playwright",
    'docker run --rm -i -v \\"$PWD:$PWD:z\\" -w \\"$PWD\\" --label dev-bot.mcp=playwright mcp/playwright --output-dir .agents/logs/playwright-mcp',
).replace(
    "--browser chromium 2>>.agents/logs/playwright-mcp.log",
    "--browser chromium --output-dir .agents/logs/playwright-mcp 2>>.agents/logs/playwright-mcp.log",
)
if after != before:
    with open(p, "w") as fh:
        fh.write(after)
    print("CHANGED")
PY
)" || out=""
    if [[ "${out}" == *CHANGED* ]]; then
      _ok "migrated the playwright launch command in $(basename "${config}")"
      changed=$((changed + 1))
    fi
  done
  [[ ${changed} -gt 0 ]] || _skip "playwright launch command already current"
}

_migrate_launch_commands

# Dependency self-heal (codebase-memory pattern, T1.2): the mcp.json fallback
# resolves a globally installed binary by explicit prefix — reinit WITHOUT a
# preceding install would register the server with no npm fallback and launch
# would fail with FATAL in .agents/logs/playwright-mcp.log.
if ! "${MODULE_DIR}/install.sh"; then
  _warn "playwright install reported a problem (see above) — npm fallback may fail"
fi

_log "Playwright MCP init complete for ${PROJECT_NAME}"
