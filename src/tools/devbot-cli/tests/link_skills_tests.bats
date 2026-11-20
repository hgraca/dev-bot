#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_skills_tests.bats
# _link_skills farms ONE LINK PER SKILL, named after the skill's frontmatter
# `name`:
#   .agents/skills/devbot/<module>/<name>  ->  <skill dir>
#
# The name is the skill's ID on an OpenCode 2 host (SkillScan derives it from the
# SKILL.md parent directory), so a `devbot:`-prefixed skill must be linked at
# `devbot:<skill>` — a plain `<skill>` directory made 82 of 84 skills unloadable
# (audit-01 FAIL-4).
#
# It must also prefer a module's machine-local generated skill dir
# (<DEV_BOT_ROOT>/storage/<module>/skills) ONLY when it carries the
# `.devbot-generated` sentinel, and prune what a module no longer ships without
# touching a foreign link or a user's own file.
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
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/skills/devbot"
}

teardown() {
  rm -r -f "${SANDBOX}"
}

@test "_link_skills: links the committed skill at its frontmatter name" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  # The link name IS the skill id the host resolves.
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify")" \
    = "${DEV_BOT_ROOT}/src/agentic/graphify/skills" ]
}

@test "_link_skills: a skill dir with a different basename still links at its frontmatter name" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/git/skills/git-commits"
  printf -- '---\nname: devbot:git-commits\n---\n' \
    > "${DEV_BOT_ROOT}/src/agentic/git/skills/git-commits/SKILL.md"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/git/"

  assert [ -L "${AGENTS_DIR}/skills/devbot/git/devbot:git-commits" ]
  # The bare directory name must NOT be what the host sees.
  refute [ -e "${AGENTS_DIR}/skills/devbot/git/git-commits" ]
}

@test "_link_skills: prefers a sentinel-marked generated storage dir" {
  mkdir -p "${DEV_BOT_ROOT}/storage/graphify/skills"
  printf -- '---\nname: devbot:graphify\n---\n' \
    > "${DEV_BOT_ROOT}/storage/graphify/skills/SKILL.md"
  : > "${DEV_BOT_ROOT}/storage/graphify/skills/.devbot-generated"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify")" \
    = "${DEV_BOT_ROOT}/storage/graphify/skills" ]
}

@test "_link_skills: relinks from committed to generated once the sentinel appears" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  mkdir -p "${DEV_BOT_ROOT}/storage/graphify/skills"
  printf -- '---\nname: devbot:graphify\n---\n' \
    > "${DEV_BOT_ROOT}/storage/graphify/skills/SKILL.md"
  : > "${DEV_BOT_ROOT}/storage/graphify/skills/.devbot-generated"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify")" \
    = "${DEV_BOT_ROOT}/storage/graphify/skills" ]
}

@test "_link_skills: does not farm a storage dir without the sentinel (signoz case)" {
  # signoz writes storage/signoz/skills for its own opencode-only wiring and has
  # no committed skills/ dir — it must not get a farm entry (duplicate skills).
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/signoz" "${DEV_BOT_ROOT}/storage/signoz/skills"
  printf 'sig\n' > "${DEV_BOT_ROOT}/storage/signoz/skills/SKILL.md"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/signoz/"

  assert [ ! -e "${AGENTS_DIR}/skills/devbot/signoz" ]
}

@test "_link_skills: writes nothing when the skills are already linked" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"
  run _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert_success
  assert_output --partial "already linked"
}

# ── Stale-entry pruning ───────────────────────────────────────────────────────

@test "_link_skills: replaces the previous module-level symlink with the per-skill dir" {
  local farm="${AGENTS_DIR}/skills/devbot/graphify"
  ln -s "${DEV_BOT_ROOT}/src/agentic/graphify/skills" "${farm}"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert [ ! -L "${farm}" ]
  assert [ -d "${farm}" ]
  assert [ -L "${farm}/devbot:graphify" ]
}

@test "_link_skills: prunes a stale module entry when the module ships no skills" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/empty-module"
  ln -s "${DEV_BOT_ROOT}/src/agentic/empty-module/skills" \
    "${AGENTS_DIR}/skills/devbot/empty-module"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/empty-module/"

  assert [ ! -e "${AGENTS_DIR}/skills/devbot/empty-module" ]
  assert [ ! -L "${AGENTS_DIR}/skills/devbot/empty-module" ]
}

@test "_link_skills: prunes a per-skill link whose skill is no longer shipped" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/graphify/skills/removed"
  printf -- '---\nname: devbot:removed\n---\n' \
    > "${DEV_BOT_ROOT}/src/agentic/graphify/skills/removed/SKILL.md"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:removed" ]

  rm -r -f "${DEV_BOT_ROOT}/src/agentic/graphify/skills/removed"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert [ ! -e "${AGENTS_DIR}/skills/devbot/graphify/devbot:removed" ]
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
}

@test "_link_skills: leaves a module entry pointing elsewhere untouched" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/empty-module" "${SANDBOX}/foreign"
  ln -s "${SANDBOX}/foreign" "${AGENTS_DIR}/skills/devbot/empty-module"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/empty-module/"

  assert [ -L "${AGENTS_DIR}/skills/devbot/empty-module" ]
  [ "$(readlink "${AGENTS_DIR}/skills/devbot/empty-module")" = "${SANDBOX}/foreign" ]
}

@test "_link_skills: leaves a foreign link inside the farm untouched" {
  mkdir -p "${SANDBOX}/foreign-skill"
  printf -- '---\nname: devbot:graphify\n---\n' > "${SANDBOX}/foreign-skill/SKILL.md"
  mkdir -p "${AGENTS_DIR}/skills/devbot/graphify"
  ln -s "${SANDBOX}/foreign-skill" "${AGENTS_DIR}/skills/devbot/graphify/mine"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/mine" ]
}

@test "_link_skills: leaves a real file at a skill name untouched" {
  mkdir -p "${AGENTS_DIR}/skills/devbot/graphify"
  printf 'keep\n' > "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  [ ! -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
  [ "$(cat "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify")" = "keep" ]
}


@test "_unlink_skills: takes a disabled module's skills out and removes its directory" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]

  _unlink_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  refute [ -e "${AGENTS_DIR}/skills/devbot/graphify" ]
}

@test "_unlink_skills: removes its own links and leaves a foreign one" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
  mkdir -p "${SANDBOX}/elsewhere"
  ln -sf "${SANDBOX}/elsewhere" "${AGENTS_DIR}/skills/devbot/graphify/devbot:foreign"

  _unlink_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  refute [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:foreign" ]
}

@test "_unlink_skills: takes back a link into the generated storage store" {
  # graphify's shape: a machine-local generated skill dir behind a sentinel.
  mkdir -p "${DEV_BOT_ROOT}/storage/gen/skills"
  printf -- '---\nname: devbot:gen\n---\n' >"${DEV_BOT_ROOT}/storage/gen/skills/SKILL.md"
  touch "${DEV_BOT_ROOT}/storage/gen/skills/.devbot-generated"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/gen"
  _link_skills "${DEV_BOT_ROOT}/src/agentic/gen/"
  assert [ -L "${AGENTS_DIR}/skills/devbot/gen/devbot:gen" ]

  _unlink_skills "${DEV_BOT_ROOT}/src/agentic/gen/"

  refute [ -e "${AGENTS_DIR}/skills/devbot/gen" ]
}

@test "_unlink_skills: takes back the legacy module-level symlink shape" {
  # The previous farm shape is one link at the module name, not a directory.
  mkdir -p "${AGENTS_DIR}/skills/devbot"
  ln -sf "${DEV_BOT_ROOT}/src/agentic/graphify/skills" \
    "${AGENTS_DIR}/skills/devbot/graphify"

  _unlink_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  refute [ -e "${AGENTS_DIR}/skills/devbot/graphify" ]
}

@test "_link_skills: does not replace a link that resolves outside the module" {
  mkdir -p "${AGENTS_DIR}/skills/devbot/graphify" "${SANDBOX}/mine"
  ln -sf "${SANDBOX}/mine" "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify"

  run _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert_output --partial "links outside this module"
  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify")" = "${SANDBOX}/mine" ]
}

@test "_link_modules: a disabled module's skills leave the farm" {
  _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]

  PROJECT_DIR="${SANDBOX}/project"
  # shellcheck disable=SC2317  # consumed by _link_modules
  _devbot_get_project_dir() { printf '.agents'; }
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() { printf '["graphify"]'; }

  _link_modules

  refute [ -e "${AGENTS_DIR}/skills/devbot/graphify" ]
}

@test "_link_skills: does not delete a module-level symlink it does not own" {
  # The legacy shape is replaced with a real directory — but a foreign link at
  # the module name is the user's, and every other path here leaves it.
  mkdir -p "${AGENTS_DIR}/skills/devbot" "${SANDBOX}/mine"
  ln -sf "${SANDBOX}/mine" "${AGENTS_DIR}/skills/devbot/graphify"

  run _link_skills "${DEV_BOT_ROOT}/src/agentic/graphify/"

  assert_output --partial "links outside this module"
  [ "$(readlink "${AGENTS_DIR}/skills/devbot/graphify")" = "${SANDBOX}/mine" ]
}

@test "_link_modules: an empty disabled set links every module" {
  # The disabled set can legitimately be empty; the loops must survive it.
  PROJECT_DIR="${SANDBOX}/project"
  # shellcheck disable=SC2317  # consumed by _link_modules
  _devbot_get_project_dir() { printf '.agents'; }
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() { printf '[]'; }

  run _link_modules

  assert_success
  assert [ -L "${AGENTS_DIR}/skills/devbot/graphify/devbot:graphify" ]
}

@test "_link_skills: prunes a legacy link into a storage dir when the module ships no skills" {
  # A sentinel-less storage/<module>/skills is not preferred, so the committed
  # skills dir is the expected one — and the no-skills branch must still
  # recognise the storage link as this module's.
  mkdir -p "${DEV_BOT_ROOT}/storage/noskills/skills" "${DEV_BOT_ROOT}/src/agentic/noskills"
  ln -sf "${DEV_BOT_ROOT}/storage/noskills/skills" "${AGENTS_DIR}/skills/devbot/noskills"

  _link_skills "${DEV_BOT_ROOT}/src/agentic/noskills/"

  refute [ -e "${AGENTS_DIR}/skills/devbot/noskills" ]
}
