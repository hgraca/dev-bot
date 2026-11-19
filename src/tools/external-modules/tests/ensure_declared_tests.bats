#!/usr/bin/env bats
# =============================================================================
# src/tools/external-modules/tests/ensure_declared_tests.bats
# `_external_module_ensure_declared` — a module's init fetches its own declared
# externals into vendor/ when the checkout is missing.
#
# The property a reader cannot see from the code: the fetch must be a no-op when
# the checkout is already there. An init runs on every reinit and on every
# `init --all`, so a network round trip per module would turn a local operation
# into a network one — and a machine offline at that moment would fail an init
# that has nothing to fetch.
#
# Hermetic: the only remote is a local bare repo inside the sandbox.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"

  SANDBOX="${BATS_TEST_TMPDIR}/sandbox"
  DEVROOT="${SANDBOX}/devbot"
  mkdir -p "${DEVROOT}"
  # shellcheck source=../functions.sh
  source "${MODULE_DIR}/functions.sh"

  # Upstream: a skills/<name>/SKILL.md tree, like the agentgateway skill.
  ORIGIN="${SANDBOX}/remotes/mod1.git"
  git init --bare -q --initial-branch=main "${ORIGIN}"
  SEED="${SANDBOX}/seed"
  git init -q --initial-branch=main "${SEED}"
  git -C "${SEED}" config user.email "test@test.com"
  git -C "${SEED}" config user.name "Test"
  git -C "${SEED}" config commit.gpgsign false
  mkdir -p "${SEED}/skills/demo-skill"
  printf 'skill\n' > "${SEED}/skills/demo-skill/SKILL.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "v1"
  git -C "${SEED}" remote add origin "${ORIGIN}"
  git -C "${SEED}" push -q origin main

  URL="file://${ORIGIN}"
  DEST="${DEVROOT}/vendor/$(_derive_vendor_path "${URL}")"
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

# Write a module's own declarations. Args: module, paths json
write_declaration() {
  local module="$1"
  local paths="${2:-{\"skills\":\"skills/demo-skill\"\}}"
  mkdir -p "${DEVROOT}/src/agentic/${module}"
  printf '{"demo-skill":{"url":"%s","paths":%s}}\n' "${URL}" "${paths}" \
    >"${DEVROOT}/src/agentic/${module}/external-modules.json"
}

@test "ensure-declared: clones a declared entry whose checkout is missing" {
  write_declaration k8s

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_success
  [ -d "${DEST}/.git" ]
  [ -f "${DEST}/skills/demo-skill/SKILL.md" ]
  [ -L "${DEVROOT}/storage/external-agentic-modules/demo-skill/skills" ]
}

@test "ensure-declared: a checkout that appears while waiting for the lock is reused" {
  write_declaration k8s
  # Another worker clones while this one waits for the lock.
  _devbot_lock_wait() {
    git clone -q "${URL}" "${DEST}"
    return 0
  }
  _install_one_module() {
    printf 'called\n' >>"${BATS_TEST_TMPDIR}/install.log"
    return 1
  }

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_success
  [ ! -f "${BATS_TEST_TMPDIR}/install.log" ]
  [ -f "${DEST}/skills/demo-skill/SKILL.md" ]
}

@test "ensure-declared: leaves an existing checkout alone and touches no network" {
  write_declaration k8s
  _external_module_ensure_declared k8s "${DEVROOT}" >/dev/null 2>&1
  [ -d "${DEST}/.git" ]
  printf 'local edit\n' > "${DEST}/skills/demo-skill/SKILL.md"
  # The mirror is re-rendered even when the checkout was already there.
  rm -rf "${DEVROOT}/storage"

  # No remote: a fetch at this point would fail, so success proves the
  # function checked the checkout instead of re-cloning it.
  rm -rf "${ORIGIN}"

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_success
  assert_output --partial "already in vendor"
  [ "$(cat "${DEST}/skills/demo-skill/SKILL.md")" = "local edit" ]
  [ -L "${DEVROOT}/storage/external-agentic-modules/demo-skill/skills" ]
}

@test "ensure-declared: a module that declares nothing is a no-op" {
  mkdir -p "${DEVROOT}/src/agentic/k8s"

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_success
  [ ! -d "${DEVROOT}/vendor" ]
}

@test "ensure-declared: reports a clone failure instead of aborting the init" {
  write_declaration k8s '{"skills":"skills/absent"}'

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_failure
  assert_output --partial "configured path 'skills=skills/absent' is missing"
}

@test "ensure-declared: a foreign checkout at the vendor path is not adopted" {
  write_declaration k8s
  mkdir -p "${DEST}"
  git init -q "${DEST}"
  git -C "${DEST}" remote add origin "https://example.com/other/repo.git"

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_failure
  assert_output --partial "belongs to"
  [ ! -f "${DEST}/skills/demo-skill/SKILL.md" ]
}

@test "ensure-declared: an invalid declared name is skipped, not mis-parsed" {
  mkdir -p "${DEVROOT}/src/agentic/k8s"
  printf '{"bad\\u000aname":{"url":"%s","paths":{"skills":"skills/demo-skill"}}}\n' "${URL}" \
    >"${DEVROOT}/src/agentic/k8s/external-modules.json"

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_failure
  assert_output --partial "invalid module name"
  [ ! -d "${DEVROOT}/vendor" ]
}

@test "ensure-declared: a local_path entry needs no clone" {
  mkdir -p "${DEVROOT}/src/agentic/k8s" "${SANDBOX}/local/skills/demo-skill"
  printf '{"local-skill":{"local_path":"%s","paths":{"skills":"skills/demo-skill"}}}\n' \
    "${SANDBOX}/local" >"${DEVROOT}/src/agentic/k8s/external-modules.json"

  run _external_module_ensure_declared k8s "${DEVROOT}"

  assert_success
  [ ! -d "${DEVROOT}/vendor" ]
}
