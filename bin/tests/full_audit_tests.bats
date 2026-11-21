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
  local id=11
  [[ "${name}" == "oc" ]] && id=12
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
  for _ in \$(seq 1 12); do echo "  evidence line"; done
} >".agents/memory/thinking/devbot-audit-${id}.md"
echo "  report written via mount → .agents/memory/thinking/devbot-audit-${id}.md"
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
  assert_output --partial "devbot-audit-11.md"
  assert_output --partial "devbot-audit-12.md"
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
  printf '#!/usr/bin/env bash\nmkdir -p .agents/memory/thinking\necho "# stub oc" > .agents/memory/thinking/devbot-audit-12.md\nexit 3\n' >"${BIN}/stub-oc.sh"
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
  assert_output --partial "devbot-audit-11.md"
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

@test "a probe file is not a report — one real report is still exit 2" {
  # Reports are devbot-audit-<NN>.md; the audit's own probes are
  # devbot-audit-probe-<NN>-*. A probe must not satisfy the pair: that is how a
  # run reported "both reports landed" with one harness never writing one.
  CC_STUB="$(_stub cc clean)"
  cat >"${BIN}/stub-oc.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/memory/thinking
echo "probe" >.agents/memory/thinking/devbot-audit-probe-09-a.md
STUB
  chmod +x "${BIN}/stub-oc.sh"
  OC_STUB="${BIN}/stub-oc.sh"

  _run

  assert_failure
  assert_equal "$status" 2
  assert_output --partial "not fixing on a partial pair"
}

# ── review blockers B2/B3 (pair attribution, FAIL-row detection) ──────────────

_stub_from() { # <name> <id> <bodyfile>
  local name="$1" id="$2" body="$3"
  cat >"${BIN}/stub-${name}.sh" <<EOF
#!/usr/bin/env bash
mkdir -p .agents/memory/thinking
{ echo "# stub report"; cat "${body}"; for _ in \$(seq 1 12); do echo "  evidence line"; done; } > ".agents/memory/thinking/devbot-audit-${id}.md"
echo "  report written via mount → .agents/memory/thinking/devbot-audit-${id}.md"
EOF
  chmod +x "${BIN}/stub-${name}.sh"
  printf '%s' "${BIN}/stub-${name}.sh"
}

@test "one harness writing two reports does not satisfy the pair" {
  # Counting new report files let a single harness fill the pair (review B2).
  cat >"${BIN}/stub-cc.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/memory/thinking
echo "| S | PASS | e |" >.agents/memory/thinking/devbot-audit-11.md
echo "| S | PASS | e |" >.agents/memory/thinking/devbot-audit-13.md
echo "  report written via mount → .agents/memory/thinking/devbot-audit-11.md"
STUB
  chmod +x "${BIN}/stub-cc.sh"
  CC_STUB="${BIN}/stub-cc.sh"
  OC_STUB="$(_stub oc silent)"

  _run

  assert_failure
  assert_equal "$status" 2
  assert_output --partial "the oc run wrote no report"
}

@test "a compound status cell containing FAIL is a FAIL row" {
  # "| Hooks | PASS + FAIL-1 |" is a finding, not a pass (review B3).
  printf '| Subsystem | Status | Evidence |\n| Hooks | PASS + FAIL-1 | dropped |\n' >"${SANDBOX}/body.md"
  CC_STUB="$(_stub_from cc 11 "${SANDBOX}/body.md")"
  OC_STUB="$(_stub_from oc 12 "${SANDBOX}/body.md")"

  _run

  assert_failure
  assert_equal "$status" 1
  assert_output --partial "PASS + FAIL-1"
}

@test "a status cell answering a question is not a FAIL row" {
  # "Yes — no FAILs." answers a question; it is not a status (review B3).
  printf '| Question | Answer | Evidence |\n| Can the agent use it? | Yes - no FAILs. | proven |\n' >"${SANDBOX}/body.md"
  CC_STUB="$(_stub_from cc 11 "${SANDBOX}/body.md")"
  OC_STUB="$(_stub_from oc 12 "${SANDBOX}/body.md")"

  _run

  assert_success
  assert_output --partial "both reports landed with no FAIL row"
}

@test "a FAILED status cell is a finding" {
  # FAILED/FAILURE used to read as clean once FAIL had to be a bare token
  # (review W-C).
  printf '| Subsystem | Status | Evidence |\n| Hooks | FAILED | dropped |\n' >"${SANDBOX}/body.md"
  CC_STUB="$(_stub_from cc 11 "${SANDBOX}/body.md")"
  OC_STUB="$(_stub_from oc 12 "${SANDBOX}/body.md")"

  _run

  assert_failure
  assert_equal "$status" 1
  assert_output --partial "FAILED"
}
