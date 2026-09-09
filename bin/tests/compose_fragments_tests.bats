#!/usr/bin/env bats
# =============================================================================
# bin/tests/compose_fragments_tests.bats
# Real-docker verification that the consumer compose fragments resolve the
# provider services they include — the up.sh discovery only -f's the fragment;
# docker compose itself resolves the `include:`. These tests exercise the REAL
# repo compose files (src/tools/ollama, src/agentic/codebase-index,
# src/tools/litellm) with `docker compose config` (parse/merge only — no
# daemon services started, no containers touched). SKIPPED when docker or
# docker compose is unavailable.
#
# Covers (verified against docker compose v2+ include semantics):
#   - codebase-index's fragment (pure include) resolves the ollama service
#   - litellm's compose + its include resolves BOTH ollama and litellm
#     (its depends_on: ollama does not dangle)
#   - merging several fragments that include the same provider does NOT
#     duplicate the service (compose dedupes by service name)
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # The fragments include ollama via the ABSOLUTE ${DEV_BOT_ROOT} path
  # (relative include: in a non-first -f file resolves against the first
  # file's dir — absolute keeps it order-independent). Export it for compose.
  export DEV_BOT_ROOT="${PROJECT_ROOT}"

  if ! command -v docker >/dev/null 2>&1; then
    skip "docker not available"
  fi
  if ! docker compose version >/dev/null 2>&1; then
    skip "docker compose not available"
  fi
}

teardown() {
  unset DEV_BOT_ROOT 2>/dev/null || true
}

@test "codebase-index fragment resolves ollama (provider boots on demand)" {
  run docker compose -f "${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml" \
    config --services
  assert_success
  assert_output "ollama"
}

@test "litellm compose + its include resolves ollama and litellm (depends_on not dangling)" {
  run docker compose -f "${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml" \
    config --services
  assert_success
  assert_output --partial "ollama"
  assert_output --partial "litellm"
}

@test "merging several fragments including the same provider does not duplicate it, in EITHER order" {
  # Simulate up.sh -f'ing both consumer fragments (codebase-index + litellm):
  # ollama is included by both — compose must dedupe to a single service.
  # Regression guard: docker compose resolves a relative include: in a
  # non-first -f file against the FIRST file's directory, so two relative
  # includes broke when codebase-index was -f'd first. The absolute
  # ${DEV_BOT_ROOT} paths make both orders work.
  local first second
  for first in \
    "${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml" \
    "${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml"; do
    if [[ "${first}" == *codebase-index* ]]; then
      second="${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml"
    else
      second="${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml"
    fi
    run docker compose -f "${first}" -f "${second}" config --services
    assert_success
    assert_output --partial "ollama"
    assert_output --partial "litellm"
    local ollama_count
    ollama_count="$(docker compose -f "${first}" -f "${second}" \
      config --services 2>/dev/null | grep -c '^ollama$' || true)"
    assert_equal "${ollama_count}" "1"
  done
}
