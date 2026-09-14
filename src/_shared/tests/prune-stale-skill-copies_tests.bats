#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/prune-stale-skill-copies_tests.bats
# Tests for _prune_stale_skill_copies() (T1.1, genericised):
#   - removes dirs matching a declared <skill-name> that carry the module's
#     declared ownership marker (including .bkp re-suffixes)
#   - declarations live PER MODULE in src/agentic/<module>/skills-prune.lst,
#     so pruning works even when the module is disabled
#   - user content protection: markerless dirs, unlisted names, wrong-marker
#     dirs are never touched
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"
  SKILLS_ROOT="${SANDBOX_DIR}/skills"
  mkdir -p "${SKILLS_ROOT}"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# shellcheck source=../functions.sh
_source_lib() {
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

_declare() {
  mkdir -p "${SANDBOX_DIR}/src/agentic/$1"
  printf '%s %s\n' "$2" "$3" >> "${SANDBOX_DIR}/src/agentic/$1/skills-prune.lst"
}

_use_sandbox_root() {
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  _source_lib
}

_make_skill_copy() {
  mkdir -p "${SKILLS_ROOT}/$1"
  [[ -n "$2" ]] && touch "${SKILLS_ROOT}/$1/$2"
}

@test "removes marker-carrying dirs incl. .bkp re-suffixes, logs each removal" {
  _make_skill_copy "graphify" ".graphify_version"
  _make_skill_copy "graphify.bkp" ".graphify_version"
  _make_skill_copy "graphify.bkp.bkp" ".graphify_version"
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success
  assert_output --partial "Removed stale"

  assert [ ! -e "${SKILLS_ROOT}/graphify" ]
  assert [ ! -e "${SKILLS_ROOT}/graphify.bkp" ]
  assert [ ! -e "${SKILLS_ROOT}/graphify.bkp.bkp" ]
}

@test "a declared but disabled module's leftovers are still pruned" {
  # no 'disabled module' logic exists here — the helper must not consult it;
  # every skills-prune.lst is honoured.
  mkdir -p "${SKILLS_ROOT}/graphify"
  touch "${SKILLS_ROOT}/graphify/.graphify_version"
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success
  assert [ ! -e "${SKILLS_ROOT}/graphify" ]
}

@test "preserves a markerless dir of the same name (possible user content)" {
  mkdir -p "${SKILLS_ROOT}/graphify"
  touch "${SKILLS_ROOT}/graphify/SKILL.md"  # no .graphify_version
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success

  assert [ -f "${SKILLS_ROOT}/graphify/SKILL.md" ]
}

@test "preserves dir carrying a DIFFERENT marker than declared" {
  _make_skill_copy "graphify" ".some_other_marker"
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success

  assert [ -e "${SKILLS_ROOT}/graphify" ]
}

@test "only declared names+markers are pruned — unrelated entries untouched" {
  _make_skill_copy "unrelated" ".graphify_version"
  _make_skill_copy "graphify-unrelated" ".graphify_version"
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success
  refute_output --partial "graphify-unrelated"

  assert [ -d "${SKILLS_ROOT}/unrelated" ]
  # 'graphify-unrelated' MUST stay: pruning must not prefix-match beyond the
  # declared name boundary... documented policy: exact name or name.bkp* only.
  assert [ -d "${SKILLS_ROOT}/graphify-unrelated" ]
}

@test "reads declarations from multiple modules" {
  _make_skill_copy "graphify" ".graphify_version"
  _make_skill_copy "othertool" ".othertool_state"
  _declare graphify graphify .graphify_version
  _declare othertool othertool .othertool_state
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success

  assert [ ! -e "${SKILLS_ROOT}/graphify" ]
  assert [ ! -e "${SKILLS_ROOT}/othertool" ]
}

@test "skips comment and blank lines in declarations" {
  mkdir -p "${SANDBOX_DIR}/src/agentic/graphify"
  {
    echo "# prune targets owned by the graphify CLI"
    echo ""
    echo "graphify .graphify_version"
  } > "${SANDBOX_DIR}/src/agentic/graphify/skills-prune.lst"
  mkdir -p "${SKILLS_ROOT}/graphify"
  touch "${SKILLS_ROOT}/graphify/.graphify_version"
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success
  assert [ ! -e "${SKILLS_ROOT}/graphify" ]
}

@test "no-ops cleanly when the skills root is absent" {
  _declare graphify graphify .graphify_version
  _use_sandbox_root

  run _prune_stale_skill_copies "${SANDBOX_DIR}/does-not-exist"
  assert_success
}

@test "no-ops cleanly when no module declares prunes" {
  mkdir -p "${SKILLS_ROOT}/graphify"
  touch "${SKILLS_ROOT}/graphify/.graphify_version"
  _use_sandbox_root

  run _prune_stale_skill_copies "${SKILLS_ROOT}"
  assert_success
  assert [ -e "${SKILLS_ROOT}/graphify" ]
}
