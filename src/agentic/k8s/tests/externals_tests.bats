#!/usr/bin/env bats
# src/agentic/k8s/tests/externals_tests.bats
# `k8s/init.sh` must leave the module's vendored skill in vendor/.
#
# The property a reader cannot see from the code: the fetch has to be safe to
# run on every reinit. A project that already has the checkout must init with no
# network at all, or an offline machine fails an init that had nothing to do.
#
# Hermetic: the only remote is a local bare repo inside the sandbox, and the
# module is exercised from a copy so the sandbox needs no real dev-bot root.
# =============================================================================

setup_file() {
  SANDBOX="${BATS_FILE_TMPDIR}/root"
  MODULE_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  REPO_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

  mkdir -p "${SANDBOX}/src/agentic" "${SANDBOX}/src/tools"
  cp -R "${MODULE_DIR}" "${SANDBOX}/src/agentic/k8s"
  cp -R "${REPO_ROOT}/src/_shared" "${SANDBOX}/src/_shared"
  cp -R "${REPO_ROOT}/src/tools/external-modules" "${SANDBOX}/src/tools/external-modules"
  # Each test declares its own entry against a local remote.
  rm -f "${SANDBOX}/src/agentic/k8s/external-modules.json"

  printf '{}\n' >"${SANDBOX}/.devbot.global.jsonc"
  mkdir -p "${SANDBOX}/home"
}

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"

  # setup_file ran in its own process; re-derive its paths. The copy itself is
  # already on disk.
  SANDBOX="${BATS_FILE_TMPDIR}/root"

  export HOME="${SANDBOX}/home"
  export DEV_BOT_ROOT="${SANDBOX}"
  export DEV_BOT_GLOBAL_CONFIG="${SANDBOX}/.devbot.global.jsonc"

  ORIGIN="${BATS_TEST_TMPDIR}/remotes/website.git"
  git init --bare -q --initial-branch=main "${ORIGIN}"
  local seed="${BATS_TEST_TMPDIR}/seed"
  git init -q --initial-branch=main "${seed}"
  git -C "${seed}" config user.email "test@test.com"
  git -C "${seed}" config user.name "Test"
  git -C "${seed}" config commit.gpgsign false
  mkdir -p "${seed}/skills/agentgateway-oss-kubernetes/references"
  printf '%s\n' '---' 'name: agentgateway-oss-kubernetes' '---' \
    >"${seed}/skills/agentgateway-oss-kubernetes/SKILL.md"
  printf 'reference\n' >"${seed}/skills/agentgateway-oss-kubernetes/references/llms.txt"
  git -C "${seed}" add -A
  git -C "${seed}" commit -qm "skill"
  git -C "${seed}" remote add origin "${ORIGIN}"
  git -C "${seed}" push -q origin main

  URL="file://${ORIGIN}"
  DEST="${SANDBOX}/vendor/$(_vendor_path "${URL}")"

  printf '{"agentgateway-oss-kubernetes":{"url":"%s","paths":{"skills":"skills/agentgateway-oss-kubernetes"}}}\n' \
    "${URL}" >"${SANDBOX}/src/agentic/k8s/external-modules.json"

  PROJECT="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${PROJECT}"
  printf '{"project_name":"demo"}\n' >"${PROJECT}/.devbot.project.jsonc"
}

teardown() {
  rm -rf "${SANDBOX}/vendor" "${SANDBOX}/storage" \
    "${SANDBOX}/src/agentic/k8s/external-modules.json" 2>/dev/null || true
}

# owner/repo, mirroring the module's own URL → vendor mapping.
_vendor_path() {
  local url="${1#file://}"
  url="${url%.git}"
  printf '%s' "${url#/}"
}

run_init() {
  run bash "${SANDBOX}/src/agentic/k8s/init.sh" "${PROJECT}"
}

@test "init: fetches the declared skill into vendor/" {
  run_init

  assert_success
  [ -d "${DEST}/.git" ]
  [ -f "${DEST}/skills/agentgateway-oss-kubernetes/SKILL.md" ]
}

@test "init: a present checkout needs no network" {
  run_init
  assert_success
  [ -f "${DEST}/skills/agentgateway-oss-kubernetes/SKILL.md" ]

  # The remote is gone: a fetch here would fail, so success proves the
  # checkout was reused rather than re-cloned.
  rm -rf "${ORIGIN}"

  run_init

  assert_success
  assert_output --partial "already in vendor"
  [ -f "${DEST}/skills/agentgateway-oss-kubernetes/SKILL.md" ]
}

@test "init: an unreachable remote warns but does not fail the init" {
  rm -rf "${ORIGIN}"

  run_init

  assert_success
  assert_output --partial "agentgateway skill not fetched into vendor/"
  [ ! -d "${DEST}" ]
}
