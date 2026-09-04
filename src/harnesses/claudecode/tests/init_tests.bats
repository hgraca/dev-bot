#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/init_tests.bats
# Tests for the claudecode harness init's _ensure_default_agent():
#   - missing .claude/settings.json -> created with DevBot, no prompt
#   - existing config with DevBot  -> skipped, untouched
#   - existing config with another agent -> non-interactive -> left as-is
#
# The interactive prompt branch is not tested (requires a TTY).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _setup_sandbox: stripped init.sh (no main body) + stubbed functions.sh,
# mirroring the pattern in bin/tests/init_tests.bats.
_setup_sandbox() {
  # Copy init.sh without the main body (from the '# ── main' header to EOF).
  sed '/^# ── main/,$d' "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" > "${SANDBOX_DIR}/init.sh"

  # Minimal functions.sh stub (MODULE_DIR = sandbox dir of the stripped copy).
  cat > "${SANDBOX_DIR}/functions.sh" <<'FUNCTIONS_EOF'
#!/usr/bin/env bash
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
FUNCTIONS_EOF

  # init.sh also sources DEV_BOT_ROOT/src/_shared/functions.sh — stub it too.
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cp "${SANDBOX_DIR}/functions.sh" "${SANDBOX_DIR}/src/_shared/functions.sh"

  mkdir -p "${SANDBOX_DIR}/.claude"
}

# _run <func> [args...]: source the stripped init.sh with PROJECT_DIR set to
# the sandbox (computed at source time from $1), then run the requested func.
_run() {
  local func="$1"
  shift
  local saved_args=("$@")

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  set -- "${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/init.sh"
  "${func}" "${saved_args[@]}"
}

# ── Tests: missing config ───────────────────────────────────────────────────

@test "default agent: missing settings.json is created with DevBot, no prompt" {
  _setup_sandbox

  run _run _ensure_default_agent
  assert_success
  assert_output --partial "default agent set to DevBot"
  refute_output --partial "Set DevBot as the default agent?"

  run python3 -c "
import json
d = json.load(open('${SANDBOX_DIR}/.claude/settings.json'))
assert d == {'agent': 'DevBot'}, d
"
  assert_success
}

@test "default agent: missing settings.json is created even in non-interactive mode" {
  _setup_sandbox
  export SKIP_CONFIRM=1

  run _run _ensure_default_agent
  assert_success
  assert_output --partial "default agent set to DevBot"

  run python3 -c "
import json
assert json.load(open('${SANDBOX_DIR}/.claude/settings.json'))['agent'] == 'DevBot'
"
  assert_success
}

# ── Tests: existing config ──────────────────────────────────────────────────

@test "default agent: existing DevBot config is skipped untouched" {
  _setup_sandbox
  printf '{\n  "agent": "DevBot",\n  "hooks": {}\n}\n' > "${SANDBOX_DIR}/.claude/settings.json"

  run _run _ensure_default_agent
  assert_success
  assert_output --partial "already DevBot"
  refute_output --partial "default agent set to DevBot"

  run python3 -c "
import json
d = json.load(open('${SANDBOX_DIR}/.claude/settings.json'))
assert d == {'agent': 'DevBot', 'hooks': {}}, d
"
  assert_success
}

@test "default agent: existing non-DevBot config left as-is when non-interactive" {
  _setup_sandbox
  printf '{\n  "agent": "build"\n}\n' > "${SANDBOX_DIR}/.claude/settings.json"

  run _run _ensure_default_agent
  assert_success
  assert_output --partial "leaving as-is (non-interactive)"
  refute_output --partial "default agent set to DevBot"

  run python3 -c "
import json
assert json.load(open('${SANDBOX_DIR}/.claude/settings.json'))['agent'] == 'build'
"
  assert_success
}

# ── skills-flatten reconcile (audit-45 §3 FAIL) ───────────────────────────────
# _link_claude_skills_flat used to rm -rf the whole .claude/skills dir on every
# reinit, so a mid-session `devbot reinit` rewrote every skill dir (new inodes)
# and the claudecode Skill tool reported "Unknown skill" for the rest of the
# session. Flattening must reconcile in place: unchanged dirs keep their
# inode/mtime across reinits. Full init.sh runs (claudecode-enabled project).

@test "skills-flatten: second init preserves skill-dir inodes (no rewrite churn)" {
  local proj sk ino1 ino2
  proj="$(mktemp -d)"
  printf '{\n  "modules": { "opencode": false, "claudecode": true }\n}\n' \
    > "${proj}/.devbot.project.jsonc"

  run bash "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" "${proj}"
  assert_success
  sk="${proj}/.claude/skills/devbot:agent-communication"
  [[ -e "${sk}/SKILL.md" ]]
  ino1="$(ls -id "${sk}" | awk '{print $1}')"
  [[ -n "${ino1}" ]]

  run bash "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" "${proj}"
  assert_success
  ino2="$(ls -id "${sk}" | awk '{print $1}')"
  [[ "${ino1}" == "${ino2}" ]]

  rm -rf "${proj}"
}

@test "skills-flatten: user real-file skill migrates once and stays at plain name" {
  local proj us
  proj="$(mktemp -d)"
  printf '{\n  "modules": { "opencode": false, "claudecode": true }\n}\n' \
    > "${proj}/.devbot.project.jsonc"
  mkdir -p "${proj}/.claude/skills/my-custom-skill"
  printf -- '---\nname: my-custom-skill\ndescription: A user skill\n---\n# My Skill\n' \
    > "${proj}/.claude/skills/my-custom-skill/SKILL.md"

  run bash "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" "${proj}"
  assert_success
  # Migrated copy in the devbot skills dir, flattened back at the plain name.
  [[ -f "${proj}/.agents/skills/my-custom-skill/SKILL.md" ]]
  us="${proj}/.claude/skills/my-custom-skill"
  [[ -L "${us}/SKILL.md" ]]

  # A second reinit must NOT .bkp-suffix its own previous flatten.
  run bash "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" "${proj}"
  assert_success
  [[ -L "${us}/SKILL.md" ]]
  refute [ -d "${proj}/.claude/skills/my-custom-skill.bkp" ]

  rm -rf "${proj}"
}
