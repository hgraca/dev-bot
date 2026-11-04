#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/module_memory_tests.bats
#
# `<devbot_dir>/memory/active/modules/` is written by every module and deleted
# by reinit, and both `devbot_dir` and the vault come from the project. A
# project that ships `devbot_dir: "../.."` or a symlinked `memory` must not be
# able to aim that write or delete outside itself — `mkdir -p` and `cp` both
# follow links, so containment is checked on every component first.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  mkdir -p "${SANDBOX}/src/_shared"

  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
_warn() { echo "WARN: $*"; }
_ok()   { true; }
_devbot_get_project_dir() { echo "${DEVBOT_DIR_STUB:-.agents}"; }
STUB
  {
    awk '/^_devbot_is_plain_relative_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_module_memory_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_write_module_memory\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_remove_legacy_module_memory\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_remove_module_memory\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  # shellcheck source=/dev/null
  source "${SANDBOX}/src/_shared/functions.sh"

  TEMPLATE="${SANDBOX}/rules.md"
  printf '# rules\n' > "${TEMPLATE}"
}

teardown() {
  rm -rf "${SANDBOX}" "${PROJECT}"
}

modules_dir() {
  printf '%s\n' "${PROJECT}/.agents/memory/active/modules"
}

@test "writes the file into the module memory folder" {
  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_success
  assert [ -f "$(modules_dir)/k8s.md" ]
  run cat "$(modules_dir)/k8s.md"
  assert_output "# rules"
}

@test "fails when the source is missing" {
  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${SANDBOX}/absent.md"

  assert_failure
  assert_output --partial "not found"
  assert [ ! -e "$(modules_dir)/k8s.md" ]
}

@test "refuses a devbot_dir with a parent traversal" {
  export DEVBOT_DIR_STUB="../elsewhere"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "not a plain relative path"
  assert [ ! -e "${PROJECT}/../elsewhere/memory/active/modules/k8s.md" ]
}

@test "refuses an absolute devbot_dir" {
  export DEVBOT_DIR_STUB="/tmp"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "not a plain relative path"
}

@test "refuses a devbot_dir that is a glob" {
  export DEVBOT_DIR_STUB="*"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "not a plain relative path"
}

@test "refuses a devbot_dir with a wildcard segment" {
  export DEVBOT_DIR_STUB=".agents/*"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "not a plain relative path"
}

@test "a dotted dir name is still accepted" {
  export DEVBOT_DIR_STUB=".ai/devbot"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_success
  assert [ -f "${PROJECT}/.ai/devbot/memory/active/modules/k8s.md" ]
}

@test "refuses a symlinked memory parent" {
  local outside
  outside="$(mktemp -d)"
  mkdir -p "${PROJECT}/.agents"
  ln -s "${outside}" "${PROJECT}/.agents/memory"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ ! -e "${outside}/active/modules/k8s.md" ]
  rm -r "${outside}"
}

@test "refuses a symlinked active folder" {
  local outside
  outside="$(mktemp -d)"
  mkdir -p "${PROJECT}/.agents/memory"
  ln -s "${outside}" "${PROJECT}/.agents/memory/active"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ ! -e "${outside}/modules/k8s.md" ]
  rm -r "${outside}"
}

@test "refuses a symlinked modules folder" {
  local outside
  outside="$(mktemp -d)"
  mkdir -p "${PROJECT}/.agents/memory/active"
  ln -s "${outside}" "${PROJECT}/.agents/memory/active/modules"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ ! -e "${outside}/k8s.md" ]
  rm -r "${outside}"
}

@test "replaces a symlinked destination instead of writing through it" {
  local outside
  outside="$(mktemp -d)"
  printf 'untouched\n' > "${outside}/victim.md"
  mkdir -p "$(modules_dir)"
  ln -s "${outside}/victim.md" "$(modules_dir)/k8s.md"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_success
  run cat "${outside}/victim.md"
  assert_output "untouched"
  refute [ -L "$(modules_dir)/k8s.md" ]
  run cat "$(modules_dir)/k8s.md"
  assert_output "# rules"
  rm -r "${outside}"
}

@test "warns instead of nesting the file when the destination is a directory" {
  mkdir -p "$(modules_dir)/k8s.md"

  run _devbot_write_module_memory "${PROJECT}" "k8s.md" "${TEMPLATE}"

  assert_failure
  assert_output --partial "is a directory"
  assert [ ! -e "$(modules_dir)/k8s.md/k8s.md" ]
}

@test "legacy removal deletes the pre-modules file" {
  mkdir -p "${PROJECT}/.agents/memory/active"
  printf '# old\n' > "${PROJECT}/.agents/memory/active/graphify.md"

  run _devbot_remove_legacy_module_memory "${PROJECT}" "graphify.md"

  assert_success
  assert [ ! -e "${PROJECT}/.agents/memory/active/graphify.md" ]
}

@test "legacy removal leaves a directory at the legacy path alone" {
  mkdir -p "${PROJECT}/.agents/memory/active/graphify.md"

  run _devbot_remove_legacy_module_memory "${PROJECT}" "graphify.md"

  assert_success
  assert [ -d "${PROJECT}/.agents/memory/active/graphify.md" ]
}

@test "legacy removal refuses a symlinked active folder" {
  local outside
  outside="$(mktemp -d)"
  printf '# old\n' > "${outside}/graphify.md"
  mkdir -p "${PROJECT}/.agents/memory"
  ln -s "${outside}" "${PROJECT}/.agents/memory/active"

  run _devbot_remove_legacy_module_memory "${PROJECT}" "graphify.md"

  assert_success
  assert [ -f "${outside}/graphify.md" ]
  rm -r "${outside}"
}

@test "module removal deletes the generated file" {
  mkdir -p "$(modules_dir)"
  printf '# old\n' > "$(modules_dir)/aws-agent-rules.md"

  run _devbot_remove_module_memory "${PROJECT}" "aws-agent-rules.md"

  assert_success
  assert [ ! -e "$(modules_dir)/aws-agent-rules.md" ]
}

@test "module removal leaves a directory at the path alone" {
  mkdir -p "$(modules_dir)/aws-agent-rules.md"

  run _devbot_remove_module_memory "${PROJECT}" "aws-agent-rules.md"

  assert_success
  assert [ -d "$(modules_dir)/aws-agent-rules.md" ]
}

@test "module removal refuses a symlinked modules folder" {
  local outside
  outside="$(mktemp -d)"
  printf '# old\n' > "${outside}/aws-agent-rules.md"
  mkdir -p "${PROJECT}/.agents/memory/active"
  ln -s "${outside}" "${PROJECT}/.agents/memory/active/modules"

  run _devbot_remove_module_memory "${PROJECT}" "aws-agent-rules.md"

  assert_success
  assert_output --partial "is a symlink"
  assert [ -f "${outside}/aws-agent-rules.md" ]
  rm -r "${outside}"
}

@test "module removal unlinks a symlink without touching its target" {
  local outside
  outside="$(mktemp -d)"
  printf 'untouched\n' > "${outside}/victim.md"
  mkdir -p "$(modules_dir)"
  ln -s "${outside}/victim.md" "$(modules_dir)/aws-agent-rules.md"

  run _devbot_remove_module_memory "${PROJECT}" "aws-agent-rules.md"

  assert_success
  assert [ ! -e "$(modules_dir)/aws-agent-rules.md" ]
  run cat "${outside}/victim.md"
  assert_output "untouched"
  rm -r "${outside}"
}
