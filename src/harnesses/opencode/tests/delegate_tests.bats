#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/delegate_tests.bats
# Tests for opencode/init.sh's _delegate_harness_dirs():
#   - devbot_dir = .agents (default): user skills in .opencode/skills are
#     migrated to .agents/skills WITHOUT a delegation symlink (opencode
#     auto-discovers .agents/skills; a symlink would double-register them)
#   - custom devbot_dir: full delegation with symlinks for all types incl.
#     skills
#
# Uses the stripped-init + stubbed-functions sandbox pattern from the
# claudecode harness tests.
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

_setup_sandbox() {
  sed '/^# ── main/,$d' "${PROJECT_ROOT}/src/harnesses/opencode/init.sh" > "${SANDBOX_DIR}/init.sh"

  cat > "${SANDBOX_DIR}/functions.sh" <<'FUNCTIONS_EOF'
#!/usr/bin/env bash
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
FUNCTIONS_EOF

  # _delegate_harness_dirs delegates to the real shared _harness_delegate_* —
  # stub those thin wrappers to record calls instead of doing real work.
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'SHARED_EOF'
#!/usr/bin/env bash
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }

# Recorded calls: "type|migrate_only" lines.
HARNESS_DELEGATE_CALLS=""

_devbot_get_project_dir() {
  if [[ -f "${SANDBOX_PROJECT_DIR}/.devbot.project.jsonc" ]]; then
    python3 -c "
import json, re, sys
raw = open('${SANDBOX_PROJECT_DIR}/.devbot.project.jsonc').read()
raw = re.sub(r'//.*', '', raw)
d = json.loads(raw)
print(d.get('devbot_dir', '.agents'))
" 2>/dev/null || echo ".agents"
  else
    echo ".agents"
  fi
}

_harness_delegate_type() {
  HARNESS_DELEGATE_CALLS="${HARNESS_DELEGATE_CALLS}${3}|${4:-false}\n"
}

_harness_delegate_to_agents() {
  local type
  for type in ${3:-agents commands skills tools}; do
    HARNESS_DELEGATE_CALLS="${HARNESS_DELEGATE_CALLS}${type}|false\n"
  done
}
SHARED_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode"
}

# _run_delegate <devbot_dir>: source the stripped init.sh with PROJECT_DIR set
# to the sandbox (devbot_dir pinned via project config) and run the function.
_run_delegate() {
  local devbot_dir="$1"
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "devbot_dir": "${devbot_dir}"
}
JSONC_EOF

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  export SANDBOX_PROJECT_DIR="${SANDBOX_DIR}"
  set -- "${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/init.sh"
  _delegate_harness_dirs
  printf '%b' "${HARNESS_DELEGATE_CALLS:-}"
}

# ── .agents devbot_dir (default): skills migrate without a symlink ──────────

@test "default .agents: skills delegated migrate-only, others symlinked" {
  _setup_sandbox

  run _run_delegate ".agents"
  assert_success

  # agents/commands/tools: full delegation
  assert_output --partial "agents|false"
  assert_output --partial "commands|false"
  assert_output --partial "tools|false"
  # skills: migrate-only (no symlink)
  assert_output --partial "skills|true"
}

# ── custom devbot_dir: full delegation for all types ────────────────────────

@test "custom devbot_dir: full delegation incl. skills" {
  _setup_sandbox

  run _run_delegate ".devbot"
  assert_success

  assert_output --partial "agents|false"
  assert_output --partial "commands|false"
  assert_output --partial "tools|false"
  # skills NOT migrate-only — full delegation applies
  assert_output --partial "skills|false"
  refute_output --partial "skills|true"
}

# ── audit-28 NOTE-2: AGENTS.md must be non-empty (referenced in instructions) ─

@test "ensure_agents_md: creates a non-empty AGENTS.md with a vault pointer when missing" {
  _setup_sandbox
  SANDBOX_PROJECT_DIR="$(mktemp -d)"
  mkdir -p "${SANDBOX_PROJECT_DIR}"
  export SANDBOX_PROJECT_DIR

  source "${SANDBOX_DIR}/init.sh"

  run _ensure_agents_md "${SANDBOX_PROJECT_DIR}"
  assert_success

  local agents="${SANDBOX_PROJECT_DIR}/AGENTS.md"
  [[ -f "$agents" ]] || fail "AGENTS.md not created"
  [[ -s "$agents" ]] || fail "AGENTS.md is empty"
  grep -q "memory/active" "$agents" || fail "AGENTS.md missing memory vault pointer"
}

@test "ensure_agents_md: leaves a user-populated AGENTS.md untouched" {
  _setup_sandbox
  SANDBOX_PROJECT_DIR="$(mktemp -d)"
  mkdir -p "${SANDBOX_PROJECT_DIR}"
  printf 'My custom agent instructions\n' > "${SANDBOX_PROJECT_DIR}/AGENTS.md"
  export SANDBOX_PROJECT_DIR

  source "${SANDBOX_DIR}/init.sh"

  run _ensure_agents_md "${SANDBOX_PROJECT_DIR}"
  assert_success

  run cat "${SANDBOX_PROJECT_DIR}/AGENTS.md"
  assert_output "My custom agent instructions"
}

@test "ensure_agents_md: fills an empty AGENTS.md (0 bytes)" {
  _setup_sandbox
  SANDBOX_PROJECT_DIR="$(mktemp -d)"
  mkdir -p "${SANDBOX_PROJECT_DIR}"
  : > "${SANDBOX_PROJECT_DIR}/AGENTS.md"
  export SANDBOX_PROJECT_DIR

  source "${SANDBOX_DIR}/init.sh"

  run _ensure_agents_md "${SANDBOX_PROJECT_DIR}"
  assert_success

  local agents="${SANDBOX_PROJECT_DIR}/AGENTS.md"
  [[ -s "$agents" ]] || fail "AGENTS.md still empty after ensure"
}
