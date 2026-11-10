#!/usr/bin/env bats
# =============================================================================
# src/agentic/argocd/tests/argocd_tests.bats
# Tests for the argocd module scripts and MCP wrappers. No cluster required.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOLS="$MODULE_DIR/tools"
  SCRIPTS="$MODULE_DIR/scripts"
}

# ── MCP wrappers ──────────────────────────────────────────────────────────────

@test "mcp-meta: every tool returns JSON with a name and args schema" {
  command -v jq &>/dev/null || skip "jq not installed"

  for tool in argocd-install argocd-start argocd-restart; do
    run bash "$TOOLS/${tool}.mcp.sh" mcp-meta
    assert_success
    echo "$output" | jq -e '.name != null' >/dev/null
    echo "$output" | jq -e '.parameters.type == "object"' >/dev/null
    echo "$output" | jq -e '.parameters.properties.args.type == "array"' >/dev/null
  done
}

@test "mcp-meta: names are unique and match the tool file" {
  command -v jq &>/dev/null || skip "jq not installed"

  for tool in argocd-install argocd-start argocd-restart; do
    name=$(bash "$TOOLS/${tool}.mcp.sh" mcp-meta | jq -r .name)
    [ "$name" = "$tool" ]
  done
}

# ── Script help / usage ───────────────────────────────────────────────────────

@test "install: --help succeeds and documents --json" {
  run bash "$SCRIPTS/argocd-install.sh" --help
  assert_success
  assert_output --partial "--json"
}

@test "start: --help succeeds and documents --token" {
  run bash "$SCRIPTS/argocd-start.sh" --help
  assert_success
  assert_output --partial "--token"
}

@test "restart: --help succeeds and documents --verify-host" {
  run bash "$SCRIPTS/argocd-restart.sh" --help
  assert_success
  assert_output --partial "--verify-host"
}

# ── Argument validation (exit code 2) ─────────────────────────────────────────

@test "restart: missing --context exits 2" {
  run bash "$SCRIPTS/argocd-restart.sh"
  assert_failure
  [ "$status" -eq 2 ]
}

@test "restart: unknown option exits 2" {
  run bash "$SCRIPTS/argocd-restart.sh" --nope
  assert_failure
  [ "$status" -eq 2 ]
}

@test "start: unknown option exits 2" {
  run bash "$SCRIPTS/argocd-start.sh" --nope
  assert_failure
  [ "$status" -eq 2 ]
}

@test "install: unknown option exits 2" {
  run bash "$SCRIPTS/argocd-install.sh" --nope
  assert_failure
  [ "$status" -eq 2 ]
}

# ── JSON contract and wrapper resolution ──────────────────────────────────────

@test "wrapper: resolves its script through a symlink" {
  tmpdir=$(mktemp -d)
  ln -sf "$TOOLS/argocd-restart.mcp.sh" "$tmpdir/argocd-restart.mcp.sh"

  run bash "$tmpdir/argocd-restart.mcp.sh" --help

  rm -f "$tmpdir/argocd-restart.mcp.sh"
  rmdir "$tmpdir"
  assert_success
  assert_output --partial "argocd-restart.sh"
}
