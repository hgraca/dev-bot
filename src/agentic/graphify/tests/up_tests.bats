#!/usr/bin/env bats
# =============================================================================
# src/agentic/graphify/tests/up_tests.bats
# Tests for the graphify module's up.sh cache prune.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  UP="${MODULE_DIR}/up.sh"

  PROJECT="$(mktemp -d)"
}

teardown() {
  rm -rf "${PROJECT}"
  return 0
}

# _ts_days_ago <n> — portable "YYYYMMDDhhmm" for n days ago, for `touch -t`.
_ts_days_ago() {
  local days="$1"
  if date -d "@0" +%Y >/dev/null 2>&1; then
    date -d "${days} days ago" +%Y%m%d%H%M
  else
    date -v-"${days}"d +%Y%m%d%H%M
  fi
}

# The prune is detached, so wait for its effect rather than racing it.
_wait_for_removal() {
  local target="$1" i=0
  while [[ -e "${target}" && ${i} -lt 100 ]]; do
    sleep 0.1
    i=$((i + 1))
  done
}

@test "up.sh: prunes cache files older than the retention window" {
  mkdir -p "${PROJECT}/graphify-out/cache/ast"
  touch "${PROJECT}/graphify-out/cache/ast/old.json" "${PROJECT}/graphify-out/cache/ast/new.json"
  touch -t "$(_ts_days_ago 10)" "${PROJECT}/graphify-out/cache/ast/old.json"

  run bash "${UP}" "${PROJECT}"
  assert_success
  assert_output --partial "older than 7d"

  _wait_for_removal "${PROJECT}/graphify-out/cache/ast/old.json"
  refute [ -e "${PROJECT}/graphify-out/cache/ast/old.json" ]
  assert [ -e "${PROJECT}/graphify-out/cache/ast/new.json" ]
}

@test "up.sh: prunes nested cache kinds and stat-index.json too" {
  mkdir -p "${PROJECT}/graphify-out/cache/semantic"
  touch "${PROJECT}/graphify-out/cache/semantic/old.json" \
    "${PROJECT}/graphify-out/cache/stat-index.json"
  touch -t "$(_ts_days_ago 30)" \
    "${PROJECT}/graphify-out/cache/semantic/old.json" \
    "${PROJECT}/graphify-out/cache/stat-index.json"

  run bash "${UP}" "${PROJECT}"
  assert_success

  _wait_for_removal "${PROJECT}/graphify-out/cache/semantic/old.json"
  _wait_for_removal "${PROJECT}/graphify-out/cache/stat-index.json"
  refute [ -e "${PROJECT}/graphify-out/cache/semantic/old.json" ]
  refute [ -e "${PROJECT}/graphify-out/cache/stat-index.json" ]
}

@test "up.sh: honours the GRAPHIFY_CACHE_MAX_AGE_DAYS override" {
  mkdir -p "${PROJECT}/graphify-out/cache/ast"
  touch "${PROJECT}/graphify-out/cache/ast/recent.json"
  touch -t "$(_ts_days_ago 3)" "${PROJECT}/graphify-out/cache/ast/recent.json"

  run env GRAPHIFY_CACHE_MAX_AGE_DAYS=1 bash "${UP}" "${PROJECT}"
  assert_success
  assert_output --partial "older than 1d"

  _wait_for_removal "${PROJECT}/graphify-out/cache/ast/recent.json"
  refute [ -e "${PROJECT}/graphify-out/cache/ast/recent.json" ]
}

@test "up.sh: no-op and success when the cache directory is absent" {
  run bash "${UP}" "${PROJECT}"
  assert_success
  refute_output --partial "pruning entries"
}

@test "up.sh: leaves files within the retention window untouched" {
  mkdir -p "${PROJECT}/graphify-out/cache/ast"
  touch "${PROJECT}/graphify-out/cache/ast/fresh.json"
  touch -t "$(_ts_days_ago 6)" "${PROJECT}/graphify-out/cache/ast/fresh.json"

  run bash "${UP}" "${PROJECT}"
  assert_success

  # Give a (would-be) detached prune time to land before asserting it did not fire.
  sleep 1
  assert [ -e "${PROJECT}/graphify-out/cache/ast/fresh.json" ]
}
