#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_skills_tests.bats
# _link_skills must prefer a module's machine-local generated skill dir
# (<DEV_BOT_ROOT>/storage/<module>/skills) ONLY when it carries the
# `.devbot-generated` sentinel — an explicit opt-in. Without the sentinel the
# committed skills/ dir is used, so a module that merely writes its own
# storage/<name>/skills (e.g. signoz) is never farmed here.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  SANDBOX="$(mktemp -d)"
  export DEV_BOT_ROOT="${SANDBOX}/devbot"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/graphify/skills"
  printf -- '---\nname: devbot:graphify\n---\n' \
    > "${DEV_BOT_ROOT}/src/agentic/graphify/skills/SKILL.md"

  # shellcheck source=../functions.sh
  source "${MODULE_DIR}/functions.sh"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "_link_skills: links the committed skills/ dir when no generated dir exists" {
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/skills/devbot"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify" ]
  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify")" = "${DEV_BOT_ROOT}/src/agentic/graphify/skills" ]
}

@test "_link_skills: prefers a sentinel-marked generated storage dir" {
  mkdir -p "${DEV_BOT_ROOT}/storage/graphify/skills"
  printf 'generated\n' > "${DEV_BOT_ROOT}/storage/graphify/skills/SKILL.md"
  : > "${DEV_BOT_ROOT}/storage/graphify/skills/.devbot-generated"
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/skills/devbot"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify")" = "${DEV_BOT_ROOT}/storage/graphify/skills" ]
}

@test "_link_skills: relinks from committed to generated once the sentinel appears" {
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/skills/devbot"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  mkdir -p "${DEV_BOT_ROOT}/storage/graphify/skills"
  : > "${DEV_BOT_ROOT}/storage/graphify/skills/.devbot-generated"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify")" = "${DEV_BOT_ROOT}/storage/graphify/skills" ]
}

@test "_link_skills: does not farm a storage dir without the sentinel (signoz case)" {
  # signoz writes storage/signoz/skills for its own opencode-only wiring and has
  # no committed skills/ dir — it must not get a farm entry (duplicate skills).
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/signoz" "${DEV_BOT_ROOT}/storage/signoz/skills"
  printf 'sig\n' > "${DEV_BOT_ROOT}/storage/signoz/skills/SKILL.md"
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/skills/devbot"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/signoz/"

  assert [ ! -e "${AGENTS_DIR}/skills/devbot/signoz" ]
}
