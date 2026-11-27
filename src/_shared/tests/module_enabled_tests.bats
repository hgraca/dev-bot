#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/module_enabled_tests.bats
# _devbot_module_enabled — the gate every tool module runs before it provisions
# anything on the machine.
#
# Two properties matter: the machine's own choice wins, and a module the RUNNING
# release ships disabled is not provisioned just because the machine's config
# has not been reconciled yet (install/update run module scripts before the
# config catches up). The gate is also independent of jq, which is optional.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  export DEV_BOT_ROOT="${SANDBOX}/root"
  mkdir -p "${DEV_BOT_ROOT}"
  export DEV_BOT_GLOBAL_CONFIG="${SANDBOX}/global.jsonc"
  printf '{}\n' >"${DEV_BOT_GLOBAL_CONFIG}"
  cd "${SANDBOX}" || return 1

  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

teardown() {
  rm -rf "${SANDBOX}"
}

_dist_modules() {
  printf '{"modules": {%s}}\n' "$1" >"${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"
}

_runtime_modules() {
  printf '{"modules": {%s}}\n' "$1" >"${DEV_BOT_GLOBAL_CONFIG}"
}

@test "a module the config names nowhere takes the shipped default" {
  _dist_modules '"herdr": false'

  run _devbot_module_enabled herdr
  assert_failure
}

@test "a module the dist ships enabled stays enabled" {
  _dist_modules '"herdr": true'

  run _devbot_module_enabled herdr
  assert_success
}

@test "the machine's own choice wins over the shipped default" {
  _dist_modules '"herdr": false'
  _runtime_modules '"herdr": true'

  run _devbot_module_enabled herdr
  assert_success
}

@test "an explicit false disables, whatever the dist says" {
  _dist_modules '"herdr": true'
  _runtime_modules '"herdr": false'

  run _devbot_module_enabled herdr
  assert_failure
}

@test "a module neither file mentions is enabled" {
  _dist_modules ''

  run _devbot_module_enabled herdr
  assert_success
}

@test "an unreadable config fails open rather than skipping the module" {
  printf 'not jsonc at all {{{\n' >"${DEV_BOT_GLOBAL_CONFIG}"

  run _devbot_module_enabled herdr
  assert_success
}

@test "the gate needs no jq" {
  # jq is not a prerequisite; a missing parser must not read as "enabled".
  _runtime_modules '"herdr": false'
  local bin="${SANDBOX}/bin"
  mkdir -p "${bin}"
  local tool
  for tool in bash sh python3 sed grep cat mktemp rm mkdir dirname; do
    [[ -n "$(command -v "${tool}" 2>/dev/null)" ]] && ln -sf "$(command -v "${tool}")" "${bin}/${tool}"
  done

  run env PATH="${bin}" bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    export DEV_BOT_GLOBAL_CONFIG='${DEV_BOT_GLOBAL_CONFIG}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_module_enabled herdr && echo ENABLED || echo DISABLED
  "

  assert_success
  assert_output "DISABLED"
}
