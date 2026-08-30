#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/start_tests.bats
# Tests for opencode/start.sh — the launcher used by `devbot` to start
# OpenCode. The session agent is not forced at launch; it comes from the
# project's opencode.jsonc `default_agent` (set during init).
#
# Validates that:
#   - start.sh launches opencode without forcing an agent
#   - extra CLI args are forwarded unchanged
#   - a missing opencode binary fails loudly with a FATAL message
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  # The script resolves the binary at ${HOME}/.opencode/bin/opencode, so
  # point HOME at a sandbox holding a fake binary that records its args.
  FAKE_HOME="$(mktemp -d)"
  FAKE_PROJECT="$(mktemp -d)"
  mkdir -p "${FAKE_HOME}/.opencode/bin"

  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"
}

teardown() {
  rm -rf "${FAKE_HOME}" "${FAKE_PROJECT}"
}

@test "start.sh launches opencode without forcing an agent" {
  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "--agent"
}

@test "start.sh forwards extra args to opencode" {
  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}" --continue
  assert_success
  assert_output "--continue"
}

@test "start.sh fails loudly when opencode binary is missing" {
  EMPTY_HOME="$(mktemp -d)"
  HOME="${EMPTY_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  rm -rf "${EMPTY_HOME}"
  assert_failure
  local combined="${output}${stderr:-}"
  [[ "${combined}" == *"opencode binary not found"* ]]
}

@test "start.sh propagates the harness exit code" {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*"
exit 42
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_failure
  [ "$status" -eq 42 ]
}

@test "start.sh alerts when the session wrote error logs" {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'ERROR: boom\n' >> .agents/logs/hooks.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "ERROR: boom"
  assert_output --partial "hooks.log"
}

# ── external_directory reconciliation (init.sh) ──────────────────────────────
# audit-22 FAIL: a /tmp/** allow placed before the catch-all "*" deny is
# shadowed (last-match-wins), leaving the pre-approved scratch dir
# unreachable. init.sh must reconcile existing configs to deny-first order on
# every reinit, not just new ones.

assert_external_directory_deny_first() {
  run python3 -c "
import json, re, sys
text = open('${FAKE_PROJECT}/opencode.jsonc').read()
m = re.search(r'\"external_directory\"\s*:\s*\{([^}]*)\}', text, re.S)
entries = json.loads('{' + m.group(1) + '}')
sys.exit(0 if list(entries.keys())[0] == '*' else 1)
"
  assert_success
}

@test "reconcile: moves /tmp/** allow after the catch-all deny (stale order)" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "/tmp/**": "allow",\n      "*": "deny"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  assert_external_directory_deny_first
}

@test "reconcile: inserts /tmp/** after the deny when absent" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "*": "deny"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  assert_external_directory_deny_first
  run grep -q '"/tmp/\*\*": "allow"' "${FAKE_PROJECT}/opencode.jsonc"
  assert_success
}
