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

# ── Compose project name: every service boots under `devbot` ─────────────────
# The compose `name:` field is only read from the FIRST -f file. A consumer
# fragment (codebase-index, litellm) can be first, so EVERY compose file that
# can be first must declare the same project name — otherwise ollama boots
# under the fragment's directory name (codebase-index / litellm), different
# invocations target different projects, and down/orphan management breaks.
# Convention: all dev-bot compose files declare `name: devbot`.

@test "every compose file declares the shared project name 'devbot'" {
  local f name found=0
  # Derived, not enumerated (review F7): a hardcoded list silently stopped
  # covering the four gateway composes added with the shared-gateway work. The
  # glob mirrors the directories bin/up.sh discovers.
  shopt -s nullglob
  for f in \
    "${PROJECT_ROOT}"/docker-compose*.yml \
    "${PROJECT_ROOT}"/src/tools/*/docker-compose*.yml \
    "${PROJECT_ROOT}"/src/agentic/*/docker-compose*.yml \
    "${PROJECT_ROOT}"/src/harnesses/*/docker-compose*.yml; do
    found=$((found + 1))
    name="$(grep -m1 '^name:' "${f}" 2>/dev/null | sed 's/^name:[[:space:]]*//')"
    [ "${name}" = "devbot" ] \
      || fail "${f#${PROJECT_ROOT}/} must declare 'name: devbot' (found: '${name}')"
  done
  shopt -u nullglob
  # Guards against a stale glob quietly covering nothing.
  [ "${found}" -gt 0 ] || fail "no compose files matched — the glob is stale"
  return 0
}

@test "the project name is devbot whichever fragment is -f'd first" {
  local first resolved
  for first in \
    "${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml" \
    "${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml"; do
    resolved="$(docker compose -f "${first}" config 2>/dev/null | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//')"
    [ "${resolved}" = "devbot" ] \
      || fail "project name from $(basename "$(dirname "${first}")")/docker-compose.yml was '${resolved}', expected 'devbot'"
  done
}

@test "the project name is devbot when both fragments are merged, either order" {
  local resolved
  resolved="$(docker compose \
    -f "${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml" \
    -f "${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml" \
    config 2>/dev/null | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//')"
  [ "${resolved}" = "devbot" ] || fail "merged (litellm first) project name was '${resolved}'"

  resolved="$(docker compose \
    -f "${PROJECT_ROOT}/src/agentic/codebase-index/docker-compose.yml" \
    -f "${PROJECT_ROOT}/src/tools/litellm/docker-compose.yml" \
    config 2>/dev/null | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//')"
  [ "${resolved}" = "devbot" ] || fail "merged (codebase-index first) project name was '${resolved}'"
}

# ── Container names: the `dev-bot-*` reclaim namespace ───────────────────────
# Each service declares a fixed `container_name`. bin/up.sh's
# _reclaim_stale_containers removes dev-bot containers left behind by a
# DIFFERENT compose project (one created before the project was renamed to
# `devbot`, or by a manual `docker run`) so their fixed name cannot wedge
# `docker compose up` — it locates them by the `dev-bot-` name prefix. A
# container named outside that namespace would be invisible to the reclaim.
# Convention: every container_name starts with `dev-bot-`.

@test "every container_name is in the dev-bot- namespace (reclaim prefix)" {
  local -a files=()
  local f
  while IFS= read -r f; do
    files+=("${f}")
  done < <(find "${PROJECT_ROOT}/src" -maxdepth 4 -name 'docker-compose*.yml' \
    -not -path '*/node_modules/*' 2>/dev/null)
  for f in "${PROJECT_ROOT}"/docker-compose*.yml; do
    [[ -f "${f}" ]] && files+=("${f}")
  done

  local found=0 name
  for f in "${files[@]}"; do
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      found=$((found + 1))
      [[ "${name}" == dev-bot-* ]] \
        || fail "${f#"${PROJECT_ROOT}/"}: container_name '${name}' must start with 'dev-bot-'"
    done < <(sed -n 's/^[[:space:]]*container_name:[[:space:]]*//p' "${f}")
  done

  [ "${found}" -gt 0 ] \
    || fail "found no container_name in any compose file — the discovery glob is wrong"
}

# ── Build contexts: a build module must resolve its OWN directory ─────────────
# bin/up.sh passes every selected compose as ONE `-f` list, and docker compose
# resolves a relative `build.context` against the FIRST file's directory — so a
# `context: .` pointed at whichever module happened to be -f'd first, and the
# build died with "failed to solve: failed to read dockerfile: open Dockerfile:
# no such file or directory". It only bites where no image exists yet (a fresh
# install, or after `docker rmi`), because an existing image means compose never
# builds — which is why every warm dev machine was fine.
# Convention: every `build.context` is anchored on the absolute ${DEV_BOT_ROOT},
# so it resolves to the module's own directory whichever file is -f'd first —
# the same rule the fragments' `include:` already follows.

# Compose files that declare a `build:` section, discovered the way bin/up.sh
# discovers them — `docker-compose*.yml`, so a GPU overlay counts too: up.sh
# appends an overlay to the same -f list as the compose it overrides.
# Derived, not enumerated, so a new build module is covered.
_build_compose_files() {
  local f
  shopt -s nullglob
  for f in "${PROJECT_ROOT}"/src/tools/*/docker-compose*.yml \
    "${PROJECT_ROOT}"/src/agentic/*/docker-compose*.yml \
    "${PROJECT_ROOT}"/src/harnesses/*/docker-compose*.yml; do
    grep -qE '^[[:space:]]*build:' "${f}" 2>/dev/null && printf '%s\n' "${f}"
  done
  shopt -u nullglob
}

@test "every build.context is anchored on an absolute path, not a relative '.'" {
  local f context found=0
  while IFS= read -r f; do
    found=$((found + 1))
    context="$(sed -n 's/^[[:space:]]*context:[[:space:]]*//p' "${f}" | head -1)"
    if [[ "${context}" != *'${DEV_BOT_ROOT}'* ]]; then
      fail "${f#"${PROJECT_ROOT}/"}: build.context '${context}' is not anchored on \${DEV_BOT_ROOT} — a relative context follows the FIRST -f file's directory, not this module's"
    fi
  done < <(_build_compose_files)
  [ "${found}" -gt 0 ] || fail "no compose with a build: section matched — the glob is stale"
  return 0
}

@test "a build service resolves its own directory as context when its compose is NOT the first -f" {
  # The fresh-install regression: ollama's compose first (up.sh discovery order
  # whenever ollama is enabled), a build module second — compose read the
  # Dockerfile out of ollama's directory instead of the module's.
  local first="${PROJECT_ROOT}/src/tools/ollama/docker-compose.yml"
  local f expected actual found=0
  while IFS= read -r f; do
    found=$((found + 1))
    expected="$(cd "$(dirname "${f}")" && pwd)"
    actual="$(docker compose -f "${first}" -f "${f}" config --format json 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(v["build"]["context"]) for v in d.get("services", {}).values() if v.get("build")]')"
    [ "${actual}" = "${expected}" ] \
      || fail "${f#"${PROJECT_ROOT}/"}: as a non-first -f its build context resolved to '${actual}', expected its own directory '${expected}'"
  done < <(_build_compose_files)
  [ "${found}" -gt 0 ] || fail "no compose with a build: section matched — the glob is stale"
  return 0
}
