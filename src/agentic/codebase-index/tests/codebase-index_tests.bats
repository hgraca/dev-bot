#!/usr/bin/env bats
# =============================================================================
# src/agentic/codebase-index/tests/codebase-index_tests.bats
# Tests for the codebase-index module (MCP-based, no local tool).
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "MCP config file exists and is valid JSON" {
  local mcp_config="$MODULE_DIR/mcp.opencode.json"
  [ -f "$mcp_config" ]

  run python3 -c "import json; json.load(open('$mcp_config')); print('VALID')"
  assert_output "VALID"
}

@test "MCP config registers codebase-index server" {
  local mcp_config="$MODULE_DIR/mcp.opencode.json"
  run grep -q 'codebase-index-mcp' "$mcp_config"
  assert_success
}

@test "install script exists" {
  [ -f "$MODULE_DIR/install.sh" ]
}

@test "init script exists" {
  [ -f "$MODULE_DIR/init.sh" ]
}

@test "skill file exists" {
  [ -f "$MODULE_DIR/skills/SKILL.md" ]
}

@test "skill file has frontmatter" {
  run head -1 "$MODULE_DIR/skills/SKILL.md"
  assert_output --partial "---"
}

# ── Integration tests (requires Ollama) ──────────────────────────────────────

ollama_reachable() {
  local ollama_api="${OLLAMA_LOCAL_API:-http://localhost:18434}"
  curl -sf "${ollama_api}/v1/models" >/dev/null 2>&1
}

@test "index without Ollama: graceful skip" {
  if ! ollama_reachable; then
    skip "Ollama not reachable"
  fi
  if [[ "${CI_CODEBASE_INDEX_INTEGRATION:-0}" != "1" ]]; then
    skip "CI_CODEBASE_INDEX_INTEGRATION not set"
  fi
  echo "Integration test: codebase index requires Ollama + CI flag"
}

@test "search without Ollama: graceful skip" {
  if ! ollama_reachable; then
    skip "Ollama not reachable"
  fi
  if [[ "${CI_CODEBASE_INDEX_INTEGRATION:-0}" != "1" ]]; then
    skip "CI_CODEBASE_INDEX_INTEGRATION not set"
  fi
  echo "Integration test: codebase search requires Ollama + CI flag"
}

@test "peek without Ollama: graceful skip" {
  if ! ollama_reachable; then
    skip "Ollama not reachable"
  fi
  if [[ "${CI_CODEBASE_INDEX_INTEGRATION:-0}" != "1" ]]; then
    skip "CI_CODEBASE_INDEX_INTEGRATION not set"
  fi
  echo "Integration test: codebase peek requires Ollama + CI flag"
}
