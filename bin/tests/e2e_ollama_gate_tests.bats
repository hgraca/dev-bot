#!/usr/bin/env bats
# =============================================================================
# bin/tests/e2e_ollama_gate_tests.bats
# Tests for the e2e launchers' host-ollama gate.
#
# The launchers (test-oc.sh / test-cc.sh) previously required host ollama
# unconditionally. Only the codebase-index engine embeds via the host ollama at
# :18434 — codebase-memory bundles its embeddings, mdctx is zero-ML, and qmd
# uses its own llama.cpp models — so the gate must fire only when the installed
# dev-bot's effective codebase_index_provider is codebase-index.
#
# The gate lives in tests/test-project/test-lib.sh and is invoked inside the
# container by test-reinit.sh; here it runs against a minimal fake install root.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  LIB="${REPO_ROOT}/tests/test-project/test-lib.sh"

  SANDBOX="$(mktemp -d)"
  # A minimal "installed dev-bot": the real shared funcs + JSONC reader, plus a
  # global config whose codebase_index_provider the tests control.
  INSTALL_ROOT="${SANDBOX}/dev-bot"
  mkdir -p "${INSTALL_ROOT}/src/_shared"
  cp "${REPO_ROOT}/src/_shared/functions.sh" \
    "${REPO_ROOT}/src/_shared/read_jsonc.py" \
    "${INSTALL_ROOT}/src/_shared/"

  # Mock curl so the gate is deterministic regardless of whether the test host
  # has ollama running. MOCK_CURL=ok → reachable; anything else → unreachable.
  MOCKBIN="${SANDBOX}/bin"
  mkdir -p "${MOCKBIN}"
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_CURL:-fail}" == "ok" ]] && exit 0
exit 7
MOCK
  chmod +x "${MOCKBIN}/curl"
  PATH="${MOCKBIN}:${PATH}"

  # shellcheck source=/dev/null
  source "${LIB}"
}

_set_provider() {
  printf '{"codebase_index_provider": "%s"}\n' "$1" > "${INSTALL_ROOT}/.devbot.global.jsonc"
}

@test "gate: codebase-memory does not require host ollama" {
  _set_provider codebase-memory

  export MOCK_CURL=fail
  run require_host_ollama_for_codebase_engine "${INSTALL_ROOT}"

  assert_success
  assert_output --partial "host ollama not required"
}

@test "gate: absent provider defaults to codebase-memory (no ollama required)" {
  rm -f "${INSTALL_ROOT}/.devbot.global.jsonc"

  export MOCK_CURL=fail
  run require_host_ollama_for_codebase_engine "${INSTALL_ROOT}"

  assert_success
  assert_output --partial "host ollama not required"
}

@test "gate: codebase-index requires host ollama — fails when unreachable" {
  _set_provider codebase-index

  export MOCK_CURL=fail
  run require_host_ollama_for_codebase_engine "${INSTALL_ROOT}"

  assert_failure
  assert_output --partial "codebase_index_provider=codebase-index"
}

@test "gate: codebase-index passes when host ollama is reachable" {
  _set_provider codebase-index

  export MOCK_CURL=ok
  run require_host_ollama_for_codebase_engine "${INSTALL_ROOT}"

  assert_success
  assert_output --partial "host ollama reachable"
}
