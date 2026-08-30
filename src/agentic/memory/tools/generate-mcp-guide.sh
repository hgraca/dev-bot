#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/tools/generate-mcp-guide.sh
# Regenerates <devbot-dir>/memory/active/mcp.md from the LIVE harness MCP
# configs — .mcp.json (claudecode) and the mcp block of opencode.jsonc
# (opencode) — so the documented server list can never silently drift from
# what is actually registered.
#
# Audit-20 FAIL: the static active/mcp.md fixture documented only 7 of 9
# registered servers (missed devbot-tools + jetbrains) and every reinit'd
# project inherited the gap. Generating the list from the live configs means
# a newly added server appears on the next reinit automatically.
#
# Known dev-bot servers get curated "Use to ..." guidance (table below);
# unrecognized servers get an honest fallback line so the file never lies
# about a server it doesn't understand.
#
# Idempotent: writes only when the output differs (a reinit in a project with
# a tracked mcp.md — e.g. the test-project fixture — must not dirty the tree
# when nothing changed).
#
# Usage: generate-mcp-guide.sh <project-dir>
#   (no-op log lines; exit 0 even when no harness configs exist yet)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This tool lives one level below the module (memory/tools/), so the root is
# four levels up from here.
DEV_BOT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

devbot_dir="$(_devbot_get_project_dir "${PROJECT_DIR}")"
OUT="${PROJECT_DIR}/${devbot_dir}/memory/active/mcp.md"

# ── Curated guidance for the known dev-bot servers ───────────────────────────
# Literal heredoc: backticks and apostrophes are preserved verbatim.
GUIDE_TABLE=$(cat <<'EOF'
chrome-devtools|Use when you need to debug or inspect a live page in a real browser — pull console errors, network requests, performance traces, or the rendered DOM; reach for this to diagnose _why_ a page misbehaves, not to drive it.
codebase-index|Use to semantically search a large or unfamiliar repo — locate the relevant files, symbols, or definitions before editing, instead of grepping blindly or guessing paths.
context7|Use to fetch current, version-accurate documentation for a library or framework before writing code against it — prevents reliance on stale or hallucinated APIs.
devbot-tools|Use to run dev-bot's own tooling — memory search (`search-memories`), git state (`git-report`), formatting (`format-md/json/yml`), `reindex-memories`, `agent-communication`, `lint-k8s`, `list-projects`, `use-case-map`; the load-bearing custom server for dev-bot workflows.
graphify|Use to search and analyze code structure — trace relationships, dependencies, call graphs, and references to understand how parts of the codebase connect and what an edit will affect.
jetbrains|Use to query and drive the local JetBrains IDE — modules, open files, symbols, call analysis, inspections, and running code via run configurations (e.g. `get_project_modules`, `search_symbol`, `lint_files`); reach for it when the task benefits from the IDE's own indexer or needs something run in the IDE.
playwright|Use to _drive_ a browser programmatically — automate multi-step flows, run end-to-end tests, fill forms, or scrape content that requires interaction; the action tool to chrome-devtools' inspection tool.
qmd|Use to search a local markdown knowledge base (notes, docs, transcripts) — hybrid keyword + semantic search with LLM reranking; reach for it to retrieve written knowledge, then fetch full documents by file. Use when you need to search your memories.
websearch|Use to retrieve current, real-world information beyond your knowledge cutoff — news, latest versions, prices, or any fact that may have changed.
EOF
)

mcp_guide() {
  local name="$1"
  local entry
  entry="$(printf '%s\n' "${GUIDE_TABLE}" | sed -n "s/^${name}|//p" | head -1)"
  if [[ -n "${entry}" ]]; then
    printf '%s' "${entry}"
  else
    printf 'No guidance documented yet — inspect its tools in the harness MCP config.'
  fi
}

# ── Collect enabled server names from the live harness configs ───────────────
SERVERS="$(
  python3 - "${PROJECT_DIR}" "${DEV_BOT_ROOT}" <<'PY'
import json, os, subprocess, sys

project, root = sys.argv[1], sys.argv[2]
servers = set()

mcp_json = os.path.join(project, ".mcp.json")
if os.path.exists(mcp_json):
    with open(mcp_json) as f:
        for name, entry in json.load(f).get("mcpServers", {}).items():
            if entry.get("enabled", True):
                servers.add(name)

opencode = os.path.join(project, "opencode.jsonc")
if os.path.exists(opencode):
    out = subprocess.run(
        [sys.executable, os.path.join(root, "src/_shared/read_jsonc.py"), opencode, "mcp"],
        capture_output=True, text=True,
    ).stdout.strip()
    if out:
        for name, entry in json.loads(out).items():
            if entry.get("enabled", True):
                servers.add(name)

print("\n".join(sorted(servers)))
PY
)"

# ── Render the guide ──────────────────────────────────────────────────────────
mkdir -p "$(dirname "${OUT}")"
OUT_TMP="${OUT}.tmp"
{
  cat <<'HEADER'
---
tags: [bootstrap, mcp]
description: MCP server tool selection and usage guide
---

# MCP Servers

## Tool Selection

HEADER
  if [[ -z "${SERVERS}" ]]; then
    printf '%s\n' "_(no MCP servers registered — run devbot reinit to wire the harness configs)_"
  else
    while IFS= read -r name; do
      [[ -z "${name}" ]] && continue
      printf -- '- **%s**: %s\n' "${name}" "$(mcp_guide "${name}")"
    done <<< "${SERVERS}"
  fi
} > "${OUT_TMP}"

# Write only if changed — a reinit must not dirty a tracked fixture (or churn
# mtimes) when the registered server set is unchanged.
if [[ -f "${OUT}" ]] && cmp -s "${OUT}" "${OUT_TMP}"; then
  rm -f "${OUT_TMP}"
  exit 0
fi

mv "${OUT_TMP}" "${OUT}"
