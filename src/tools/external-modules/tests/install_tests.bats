#!/usr/bin/env bats
# =============================================================================
# src/tools/external-modules/tests/install_tests.bats
# Tests for the install/update entry points: install.sh (used by `devbot
# install`, `devbot update` and the start-time self-update) and
# `devbot module install`. Both must share the validated update path.
#
# Hermetic: every remote is a local bare repo inside the sandbox.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  INSTALL="${MODULE_DIR}/install.sh"
  MODULE_TOOL="${MODULE_DIR}/tools/module.sh"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"

  SANDBOX="$(mktemp -d)"
  DEVROOT="${SANDBOX}/devbot"
  mkdir -p "${DEVROOT}"
  export DEV_BOT_ROOT="${DEVROOT}"
  # shellcheck source=../functions.sh
  source "${MODULE_DIR}/functions.sh"

  ORIGIN="${SANDBOX}/remotes/mod1.git"
  git init --bare -q --initial-branch=main "${ORIGIN}"

  SEED="${SANDBOX}/seed"
  git init -q --initial-branch=main "${SEED}"
  git -C "${SEED}" config user.email "test@test.com"
  git -C "${SEED}" config user.name "Test"
  git -C "${SEED}" config commit.gpgsign false
  git -C "${SEED}" config tag.gpgSign false

  mkdir -p "${SEED}/skills" "${SEED}/agents"
  printf 'v1\n' > "${SEED}/skills/SKILL.md"
  printf 'readme\n' > "${SEED}/skills/README.md"
  printf 'agent\n' > "${SEED}/agents/AGENT.md"
  printf 'readme\n' > "${SEED}/agents/README.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "v1"
  git -C "${SEED}" remote add origin "${ORIGIN}"
  git -C "${SEED}" push -q origin main

  URL="file://${ORIGIN}"
  DEST="${DEVROOT}/vendor/$(_derive_vendor_path "${URL}")"
  STORAGE="${DEVROOT}/storage/external-agentic-modules/mod1"

  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

write_config() {
  printf '%s\n' "${1:-}" > "${DEVROOT}/.devbot.global.jsonc"
}

# Remove a directory from the seed repo and publish the change.
remove_upstream() {
  local path="$1"
  local message="$2"
  git -C "${SEED}" rm -rq "${path}"
  git -C "${SEED}" commit -qm "${message}"
  git -C "${SEED}" push -q origin main
}

# ── install.sh ────────────────────────────────────────────────────────────────

@test "install: clones the module, renders its mirror and stamps the check" {
  run bash "${INSTALL}"

  assert_success
  [ -d "${DEST}/.git" ]
  [ -L "${STORAGE}/skills" ]
  [ -f "${DEVROOT}/storage/run/external-modules.checked" ]
  # The stamp records the configuration it covered.
  [ -f "${DEVROOT}/storage/run/external-modules.checked.entries" ]
}

@test "install: cancels an update whose configured path disappeared upstream" {
  run bash "${INSTALL}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  remove_upstream skills "move skills away"

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "configured path 'skills=skills' is missing in the incoming version"
  assert_output --partial "update cancelled — keeping the current checkout"
  # The legacy checkout and the mirror into it survive.
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
  [ -f "${STORAGE}/skills/SKILL.md" ]
}

@test "install: validates every alias entry's configured paths" {
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'
  run bash "${INSTALL}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  remove_upstream agents "drop agents"

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "configured path 'agents=agents' is missing"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -d "${DEST}/agents" ]
}

# ── devbot module install ────────────────────────────────────────────────────

@test "module install: uses the same validated update path" {
  run bash "${INSTALL}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  remove_upstream skills "move skills away"

  run bash "${MODULE_TOOL}" install

  assert_failure
  assert_output --partial "configured path 'skills=skills' is missing in the incoming version"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
}

@test "install: renders the mirror of a local-path module" {
  mkdir -p "${SANDBOX}/local-source/skills"
  printf 'local\n' > "${SANDBOX}/local-source/skills/SKILL.md"
  write_config '{"external_modules":{"local-one":{"local_path":"'"${SANDBOX}"'/local-source","paths":{"skills":"skills"}}}}'

  run bash "${INSTALL}"

  assert_success
  [ -L "${DEVROOT}/storage/external-agentic-modules/local-one/skills" ]
  [ "$(cat "${DEVROOT}/storage/external-agentic-modules/local-one/skills/SKILL.md")" = "local" ]
}

@test "install: prunes READMEs for every alias's configured paths" {
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${INSTALL}"

  assert_success
  [ ! -e "${DEST}/skills/README.md" ]
  [ ! -e "${DEST}/agents/README.md" ]
}

@test "install: refuses a retained checkout that belongs to another repository" {
  run bash "${INSTALL}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"
  git -C "${DEST}" remote set-url origin "file://${SANDBOX}/other.git"

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "belongs to"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
}

@test "install: fails when a local module's source directory is gone" {
  write_config '{"external_modules":{"local-one":{"local_path":"'"${SANDBOX}"'/gone","paths":{"skills":"skills"}}}}'

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "local path not found"
  # Nothing synced means no stamp: the next start checks again.
  [ ! -f "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "install: fails for a URL that would escape the vendor root" {
  write_config '{"external_modules":{"escape":{"url":"file://'"${SANDBOX}"'/../../outside.git","paths":{"skills":"skills"}}}}'

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "does not map inside vendor/"
  [ ! -f "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "install: refuses a module name that is not a single path component" {
  write_config '{"external_modules":{"../escape":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'

  run bash "${INSTALL}"

  assert_failure
  assert_output --partial "invalid module name"
  [ ! -e "${SANDBOX}/escape" ]
}
