#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp_declares_hybrid_tests.bats
# Tests for _mcp_declares_hybrid — the predicate both harness inits use to
# exempt a hybrid MCP server from their docker-only registration guard.
#
# The guard exists so an MCP that can ONLY run under docker is not registered
# on a host without a daemon, where the client would log connection errors for
# a server that cannot start. A hybrid server — one whose own launcher picks
# between a docker path and a non-docker fallback at runtime — must stay
# registered in that case.
#
# The guard used to grep the translated command for the literal
# `npx -y @playwright/mcp`. e7e7cd40 replaced that fallback, so the literal
# stopped matching, playwright was misclassified as docker-only, and — once the
# stale-refresh list began dropping its outdated entry — the server would be
# dropped on every daemon-less host. The declaration is now explicit: the
# server carries `"_hybrid": true` in its canonical manifest.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  WORK="$(mktemp -d)"
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

teardown() {
  rm -rf "${WORK}"
}

# _manifest <json> — write a canonical manifest into the work dir, echo path.
_manifest() {
  printf '%s' "$1" > "${WORK}/mcp.json"
  echo "${WORK}/mcp.json"
}

@test "playwright's real manifest declares a hybrid (regression: e7e7cd40 removed the literal the guard keyed on)" {
  run _mcp_declares_hybrid "${PROJECT_ROOT}/src/agentic/playwright/mcp.json" playwright
  assert_success
}

@test "playwright's real manifest is hybrid without a key (claudecode's per-module form)" {
  run _mcp_declares_hybrid "${PROJECT_ROOT}/src/agentic/playwright/mcp.json"
  assert_success
}

@test "a manifest without the annotation is not hybrid" {
  run _mcp_declares_hybrid "${PROJECT_ROOT}/src/agentic/mdctx/mcp.json" mdctx
  assert_failure
}

@test "missing manifest is not hybrid" {
  run _mcp_declares_hybrid "${WORK}/absent.json" anything
  assert_failure
}

@test "unknown server key in a hybrid manifest is not hybrid" {
  run _mcp_declares_hybrid "${PROJECT_ROOT}/src/agentic/playwright/mcp.json" not-a-server
  assert_failure
}

@test "only the literal boolean true counts as hybrid" {
  local m
  m="$(_manifest '{"mcp":{"s":{"type":"stdio","_hybrid":false,"command":["x"]}}}')"

  run _mcp_declares_hybrid "$m" s
  assert_failure
}

@test "a hybrid server marks its whole manifest for the any-server form" {
  local m
  m="$(_manifest '{"mcp":{"plain":{"type":"stdio","command":["x"]},"mixed":{"type":"stdio","_hybrid":true,"command":["y"]}}}')"

  run _mcp_declares_hybrid "$m"
  assert_success

  run _mcp_declares_hybrid "$m" plain
  assert_failure

  run _mcp_declares_hybrid "$m" mixed
  assert_success
}

@test "malformed manifest is not hybrid (fails safe — never wrongly exempts a docker-only server)" {
  local m
  m="$(_manifest 'not json at all')"

  run _mcp_declares_hybrid "$m" s
  assert_failure
}
