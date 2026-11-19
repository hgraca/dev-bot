#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_nested_tests.bats
# nested projects: one copy per plugin id.
#
# A v2 host discovers every ancestor's .opencode/plugins/, so a dev-bot project
# inside another must not write a duplicate of a plugin the ancestor supplies.
#
# Split from init_tests.bats: bats parallelises across files only, and that file
# backed the suite's wall clock. Scenarios and seeds come from init_test_helper.
# =============================================================================

load "${BATS_TEST_DIRNAME}/../../../_shared/tests/lib/scenario"
load 'init_test_helper'

# ── Nested projects: one copy per plugin id ───────────────────────────────────
# A v2 host discovers every ancestor's `.opencode/plugins/` package, so a dev-bot
# project nested inside another dev-bot project loads two copies of each plugin.
# The host keeps the first and fails the second with "Duplicate plugin ID", which
# the TUI shows as a failed plugin. The ancestor's copy is location-scoped, so it
# serves the nested project too; the nested init must not write a duplicate.

_nested_projects() {
  PARENT="${PROJECT}/parent"
  CHILD="${PARENT}/child"
  mkdir -p "${CHILD}"
  printf '{ "harness": "opencode-v2" }\n' > "${PARENT}/.devbot.project.jsonc"
  printf '{ "harness": "opencode-v2" }\n' > "${CHILD}/.devbot.project.jsonc"
}

# _ancestor_package <name> <target> [marker 0|1] [manifest name]
# Hand-writes a plugin package so a test can vary one detection guard at a time.
# The manifest is compact on purpose: init must not depend on its formatting.
_ancestor_package() {
  local name="$1" target="$2" marker="${3:-1}"
  local manifest="${4:-devbot-${name}}"
  local dir="${PARENT}/.opencode/plugins/${name}"
  mkdir -p "${dir}"
  if [[ "${marker}" == "1" ]]; then
    printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${dir}/index.ts"
  else
    printf '%s\n' "// hand-written by the project" > "${dir}/index.ts"
  fi
  printf 'export { default } from "%s"\n' "${target}" >> "${dir}/index.ts"
  printf '{"name":"%s","version":"0.0.0","type":"module","exports":{".":"./index.ts"}}\n' \
    "${manifest}" > "${dir}/package.json"
}

@test "init does not duplicate a plugin an ancestor project already supplies" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  local name
  for name in on-hooks mcp-sync skill-name-resolver; do
    assert [ -d "${PARENT}/.opencode/plugins/${name}" ]
    refute [ -e "${CHILD}/.opencode/plugins/${name}" ]
  done
}

@test "init removes its own plugin copies once an ancestor supplies them" {
  # The historical shape: the nested project was initialised first, so it owns a
  # copy of every plugin before the ancestor is initialised.
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null
  assert [ -d "${CHILD}/.opencode/plugins/on-hooks" ]

  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  local name
  for name in on-hooks mcp-sync skill-name-resolver; do
    refute [ -e "${CHILD}/.opencode/plugins/${name}" ]
    # The ancestor keeps the only copy.
    assert [ -d "${PARENT}/.opencode/plugins/${name}" ]
  done
}

@test "an ancestor shim without the dev-bot marker does not count as supplying" {
  _nested_projects
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  _ancestor_package on-hooks "${target}" 0
  # Pin the fixture: the marker is the only guard failing here.
  grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-on-hooks"' "${PARENT}/.opencode/plugins/on-hooks/package.json"
  refute grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "an ancestor package with another manifest name does not count as supplying" {
  _nested_projects
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  _ancestor_package on-hooks "${target}" 1 someone-elses-plugin
  # Pin the fixture: the manifest name is the only guard failing here.
  grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"
  grep -qE '"name":"someone-elses-plugin"' "${PARENT}/.opencode/plugins/on-hooks/package.json"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "an ancestor shim whose target is gone does not suppress this project's copy" {
  # A moved or deleted toolkit checkout leaves a package that cannot import, so it
  # holds no plugin id and the nested project must still write its own copy.
  _nested_projects
  _ancestor_package on-hooks "${PROJECT}/gone/on-hooks.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "which is gone"

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "init warns when an ancestor supplies a different dev-bot build" {
  # The host loads the ancestor's copy first, so the nested project follows that
  # build; init still has to say so instead of silently changing version.
  _nested_projects
  local other="${PROJECT}/other-dev-bot/src/hooks"
  mkdir -p "${other}"
  printf 'export default { id: "devbot-hooks", setup() {} }\n' > "${other}/on-hooks.ts"
  _ancestor_package on-hooks "${other}/on-hooks.ts"
  assert [ -f "${PARENT}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"
  grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-on-hooks"' "${PARENT}/.opencode/plugins/on-hooks/package.json"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "runs a different dev-bot build"
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "a symlinked spelling of the same build is not reported as different" {
  # The same checkout reached through a symlinked directory must not warn: a
  # string compare would, because the shim records the spelling used at its init.
  _nested_projects
  local link="${PROJECT}/dev-bot-shortcut"
  ln -s "${DEV_BOT_ROOT}" "${link}"
  _ancestor_package on-hooks "${link}/src/harnesses/opencode-v2/hooks/on-hooks.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  refute_output --partial "runs a different dev-bot build"
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "init leaves a user's package alone when an ancestor supplies the plugin" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  mkdir -p "${CHILD}/.opencode/plugins/on-hooks"
  printf 'export default { id: "my-own-on-hooks" }\n' > "${CHILD}/.opencode/plugins/on-hooks/index.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "duplicate registration may persist"

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "my-own-on-hooks" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
  # The ancestor keeps its own copy untouched too.
  assert [ -f "${PARENT}/.opencode/plugins/on-hooks/index.ts" ]
}

@test "init never removes a symlinked plugin directory shadowing an ancestor's copy" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  mkdir -p "${PROJECT}/outside/on-hooks"
  printf 'export default { id: "outside-on-hooks" }\n' > "${PROJECT}/outside/on-hooks/index.ts"
  mkdir -p "${CHILD}/.opencode/plugins"
  ln -sfn "${PROJECT}/outside/on-hooks" "${CHILD}/.opencode/plugins/on-hooks"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -L "${CHILD}/.opencode/plugins/on-hooks" ]
  assert [ -f "${PROJECT}/outside/on-hooks/index.ts" ]
}

@test "a huge ancestor shim does not abort init on a broken pipe" {
  # `sed | head` stops reading at the first match; a long shim then makes sed
  # take SIGPIPE, and pipefail would surface 141 as a failed init.
  _nested_projects
  local dir="${PARENT}/.opencode/plugins/on-hooks"
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  mkdir -p "${dir}"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${dir}/index.ts"
  local i
  for ((i = 0; i < 2000; i++)); do
    printf 'export { default } from "%s"\n' "${target}" >> "${dir}/index.ts"
  done
  printf '{"name":"devbot-on-hooks","version":"0.0.0","type":"module","exports":{".":"./index.ts"}}\n' > "${dir}/package.json"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "a project with no ancestor dev-bot plugins still gets every plugin" {
  # The nesting guard must not suppress the normal, non-nested install.
  scenario default

  local name
  for name in on-hooks mcp-sync skill-name-resolver; do
    assert [ -d "${PROJECT}/.opencode/plugins/${name}" ]
  done
}

@test "init says the harness must restart after retiring a plugin copy" {
  # The host registered the duplicate when it started; removing the package on
  # disk leaves the failed entry until the harness reloads its plugins.
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"

  assert_success
  assert_output --partial "restart the harness"
}
