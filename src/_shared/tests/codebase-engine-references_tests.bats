#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/codebase-engine-references_tests.bats
#
# The codebase engine is chosen at runtime by `codebase_index_provider` — either
# `codebase-index` (Ollama semantic index) or `codebase-memory` (tree-sitter
# graph). The two engines share ONE skill slot, `devbot:codebase-index`, and each
# engine's own skill documents that engine's MCP tools. Instructions that name
# one engine's tools are therefore wrong on half the flips.
#
# This bit, hard: `gather-context` told scout to "use the `codebase-index` MCP
# tools" while the default provider had already moved to `codebase-memory`, so
# every scout run reached a semantic index with no embedding provider and
# errored. The route must stay the shared slot; tool names belong in the engine
# skills.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

  # Instructions that route an agent at the codebase engine. Every one must go
  # through the shared slot.
  SLOT_REFERENCING_FILES=(
    "src/agentic/explore/skills/gather-context/SKILL.md"
    "src/agentic/explore/skills/search-code/SKILL.md"
    "src/agentic/devteam/agents/scout.md"
  )

  # The subset that must not name ANY engine's MCP tool. search-code is excluded
  # on purpose: it enumerates each engine's representative tools, clearly
  # labelled per engine, to contrast them.
  NO_TOOL_NAMES_FILES=(
    "src/agentic/explore/skills/gather-context/SKILL.md"
    "src/agentic/devteam/agents/scout.md"
  )
}

# MCP tool names belonging to exactly ONE engine — codebase-index (semantic
# index) or codebase-memory (graph). Matched in backticks so prose like "call
# graph" or "search graph" cannot trip the scan.
_ENGINE_TOOLS=(
  codebase_search codebase_peek codebase_context implementation_lookup
  find_similar call_graph index_codebase
  search_graph search_code trace_path get_architecture get_code_snippet
  query_graph detect_changes get_graph_schema
)

@test "gather-context, search-code and scout route to the shared devbot:codebase-index slot" {
  local missing="" rel
  for rel in "${SLOT_REFERENCING_FILES[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/${rel}" ]]; then
      missing+="${rel} (absent)\n"
      continue
    fi
    grep -qF 'devbot:codebase-index' "${PROJECT_ROOT}/${rel}" || missing+="${rel}\n"
  done
  if [[ -n "${missing}" ]]; then
    printf 'Not routing through the shared codebase slot:\n%b' "${missing}" >&2
    fail "codebase-engine instructions must reference devbot:codebase-index"
  fi
}

@test "gather-context and scout name no engine-specific codebase tool" {
  local hits="" rel tool
  for rel in "${NO_TOOL_NAMES_FILES[@]}"; do
    for tool in "${_ENGINE_TOOLS[@]}"; do
      if grep -qF "\`${tool}\`" "${PROJECT_ROOT}/${rel}"; then
        hits+="${rel}: \`${tool}\`\n"
      fi
    done
  done
  if [[ -n "${hits}" ]]; then
    printf 'Engine-specific tool names in provider-agnostic instructions:\n%b' "${hits}" >&2
    fail "name the engine skill, not its tools — the engine flips with config"
  fi
}

# The exact phrasing that caused the bug: an engine named as the source of its
# "MCP tools". A reworded tool name is caught by the test above; this catches the
# direct form so the regression cannot return verbatim.
@test "no instruction names an engine as the source of its MCP tools" {
  local hits="" rel
  for rel in "${SLOT_REFERENCING_FILES[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/${rel}" ]]; then
      continue
    fi
    if grep -qE '`codebase-(index|memory)` MCP tools' "${PROJECT_ROOT}/${rel}"; then
      hits+="${rel}\n"
    fi
  done
  if [[ -n "${hits}" ]]; then
    printf 'Engine named as the MCP-tools source:\n%b' "${hits}" >&2
    fail "route through the shared slot, never name the engine's tools"
  fi
}

# Guard against a scan that checks nothing: a renamed/moved fixture or a shrunk
# token list would otherwise pass silently.
@test "the scan is not vacuous (fixtures exist and the token list is intact)" {
  local rel
  for rel in "${SLOT_REFERENCING_FILES[@]}"; do
    [[ -s "${PROJECT_ROOT}/${rel}" ]] || fail "missing or empty fixture: ${rel}"
  done
  local covered="${#SLOT_REFERENCING_FILES[@]}" banned="${#_ENGINE_TOOLS[@]}"
  (( covered >= 3 )) || fail "expected at least 3 slot-referencing files, scanned ${covered}"
  (( banned >= 10 )) || fail "engine-tool list shrank unexpectedly: ${banned}"
}
