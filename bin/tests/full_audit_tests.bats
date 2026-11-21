#!/usr/bin/env bats
# =============================================================================
# bin/tests/full_audit_tests.bats
# tests/test-project/full-audit.sh — the parallel cc+oc audit runner: it must
# require BOTH reports before a fix, and tell a clean pair from FAIL rows from a
# partial pair. Launchers and docker are stubbed, so nothing is audited here.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  BIN="${SANDBOX}/bin"
  mkdir -p "${BIN}" "${SANDBOX}/.agents/memory/thinking"

  # The runner resolves its report dir from its own location, so it runs from a
  # copy and writes into the sandbox.
  cp "${REPO_ROOT}/tests/test-project/full-audit.sh" "${SANDBOX}/full-audit.sh"
  chmod +x "${SANDBOX}/full-audit.sh"

  # A launcher may build the image; the stub daemon always has it.
  printf '#!/usr/bin/env bash\nexit 0\n' >"${BIN}/docker"
  chmod +x "${BIN}/docker"
}

teardown() {
  rm -rf "${SANDBOX}"
}

# _stub <name> <clean|fail|silent|error> — a launcher that writes (or does not
# write) that harness's report, named after the harness so the runner's
# before/after diff sees it.
_stub() {
  local name="$1" mode="$2"
  cat >"${BIN}/stub-${name}.sh" <<EOF
#!/usr/bin/env bash
echo "stub ${name} \$*"
if [[ "${mode}" == "error" ]]; then
  exit 3
fi
if [[ "${mode}" == "silent" ]]; then
  exit 0
fi
mkdir -p .agents/memory/thinking
{
  echo "# stub ${name} report"
  echo "| Subsystem | Status | Evidence |"
  if [[ "${mode}" == "fail" ]]; then
    echo "| Hooks | **FAIL** | probe fired but the file stayed unformatted |"
  else
    echo "| Hooks | PASS | probe fired and the file was reformatted |"
  fi
} >".agents/memory/thinking/devbot-audit-${name}.md"
EOF
  chmod +x "${BIN}/stub-${name}.sh"
  printf '%s' "${BIN}/stub-${name}.sh"
}

# An under-budget session by default: the budget gate must not decide these
# tests, and a missing usage tool would only print "unknown".
_usage_stub() {
  printf '%s\n' '#!/usr/bin/env bash' "echo '{\"percent\": ${1:-40}}'" >"${BIN}/usage"
  chmod +x "${BIN}/usage"
  printf '%s' "${BIN}/usage"
}

_run() {
  run env PATH="${BIN}:${PATH}" \
    FULL_AUDIT_CC_LAUNCHER="${CC_STUB}" \
    FULL_AUDIT_OC_LAUNCHER="${OC_STUB}" \
    FULL_AUDIT_USAGE_TOOL="$(_usage_stub "${USAGE_PERCENT:-40}")" \
    "${SANDBOX}/full-audit.sh" "$@"
}

@test "a clean pair exits 0 and names both reports" {
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc clean)"

  _run

  assert_success
  assert_output --partial "devbot-audit-cc.md"
  assert_output --partial "devbot-audit-oc.md"
  assert_output --partial "both reports landed with no FAIL row"
}

@test "a FAIL row in either report exits 1 and prints the row" {
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc fail)"

  _run

  assert_failure
  assert_equal "$status" 1
  assert_output --partial "1 FAIL row(s)"
  assert_output --partial "probe fired but the file stayed unformatted"
}

@test "one report landing is exit 2 — never fix on a partial pair" {
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc silent)"

  _run

  assert_failure
  assert_equal "$status" 2
  assert_output --partial "not fixing on a partial pair"
}

@test "a launcher failure is exit 2 even when both reports landed" {
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc error)"
  # The failing launcher still leaves a clean report behind for its harness, so
  # the run is judged on the exit code, not on the file count alone.
  printf '#!/usr/bin/env bash\nmkdir -p .agents/memory/thinking\necho "# stub oc" > .agents/memory/thinking/devbot-audit-oc.md\nexit 3\n' >"${BIN}/stub-oc.sh"
  chmod +x "${BIN}/stub-oc.sh"

  _run

  assert_failure
  assert_equal "$status" 2
  assert_output --partial "a launcher failed"
}

@test "--no-oc requires only the cc report" {
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc silent)"

  _run --no-oc

  assert_success
  assert_output --partial "devbot-audit-cc.md"
}

@test "the audit model defaults to sonnet" {
  run grep -qF 'DEVBOT_TEST_CLAUDE_MODEL="${DEVBOT_TEST_CLAUDE_MODEL:-sonnet}"' \
    "${SANDBOX}/full-audit.sh"

  assert_success
}

@test "a spent session budget exits 3 before any audit runs" {
  USAGE_PERCENT=75
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc clean)"

  _run

  assert_failure
  assert_equal "$status" 3
  assert_output --partial "past 70%"
  run find "${SANDBOX}/.agents/memory/thinking" -name 'devbot-audit-*.md'
  assert_output ""
}

@test "the budget is configurable and defaults to 70%" {
  USAGE_PERCENT=65
  CC_STUB="$(_stub cc clean)"
  OC_STUB="$(_stub oc clean)"

  _run

  assert_success
  assert_output --partial "session at 65% (budget 70%)"
}
