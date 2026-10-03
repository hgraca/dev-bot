#!/usr/bin/env bats
# =============================================================================
# bin/tests/install_version_tests.bats
# _setup_devbot_config records the release tag when the checkout sits exactly on
# one, so a tag install carries a version without waiting for `devbot update`
# (audit-69 NOTE-8).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  cp "${PROJECT_ROOT}/src/_shared/functions.sh" "${SANDBOX}/src/_shared/functions.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/src/_shared/read_jsonc.py"
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/install.sh" > "${SANDBOX}/bin/install.sh"
  printf '{\n  "version": "",\n  "gpu_enabled": false\n}\n' > "${SANDBOX}/.devbot.global.dist.jsonc"

  git -C "${SANDBOX}" init -q
  git -C "${SANDBOX}" -c user.email=t@t -c user.name=t add -A
  git -C "${SANDBOX}" -c user.email=t@t -c user.name=t commit -q -m init
}

teardown() {
  rm -rf "${SANDBOX}"
}

_read_config_version() {
  python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
print(repr(load_jsonc('${SANDBOX}/.devbot.global.jsonc')['version']))
"
}

@test "install: stamps the release tag into the global config" {
  git -C "${SANDBOX}" tag v1.2.3

  run bash -c "source '${SANDBOX}/bin/install.sh' && _setup_devbot_config"
  assert_success

  run _read_config_version
  assert_output "'v1.2.3'"
}

@test "install: leaves version empty on a checkout that is not at a tag" {
  run bash -c "source '${SANDBOX}/bin/install.sh' && _setup_devbot_config"
  assert_success

  run _read_config_version
  assert_output "''"
}

@test "install: writes the global config before running module prereqs" {
  # audit-80 N7: on a fresh install the config did not exist yet when
  # _run_module_prereqs ran, so a disabled module (sentry) still printed its
  # prerequisites. The config must be written first so the disabled set is known.
  local cfg_line prereq_line
  cfg_line="$(grep -n '^  _setup_devbot_config$' "${PROJECT_ROOT}/bin/install.sh" | tail -1 | cut -d: -f1)"
  prereq_line="$(grep -n '^  _run_module_prereqs$' "${PROJECT_ROOT}/bin/install.sh" | tail -1 | cut -d: -f1)"
  [ -n "${cfg_line}" ] && [ -n "${prereq_line}" ] && [ "${cfg_line}" -lt "${prereq_line}" ]
}
