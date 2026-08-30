#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/skills_flat_tests.bats
# Tests for _link_claude_skills_flat()'s preservation of user custom skills:
#   - a real user skill dir in .claude/skills is migrated to devbot_dir/skills
#     BEFORE the flat rebuild (which drops .claude/skills), then flattened back
#   - dev-bot's own flat links (symlinked SKILL.md) are NOT migrated
#   - already-migrated skills are not duplicated on re-init (idempotent)
#   - name collisions: existing devbot_dir skill wins, user's kept as .bkp
#
# Uses the stripped-init + stubbed-functions sandbox pattern from init_tests.
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
  # Copy init.sh without the main body (from the '# ── main' header to EOF).
  sed '/^# ── main/,$d' "${PROJECT_ROOT}/src/harnesses/claudecode/init.sh" > "${SANDBOX_DIR}/init.sh"

  # Stub functions.sh — _link_claude_skills_flat needs the output helpers plus
  # _devbot_get_project_dir (defaults to .agents here).
  cat > "${SANDBOX_DIR}/functions.sh" <<'FUNCTIONS_EOF'
#!/usr/bin/env bash
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_devbot_get_project_dir() { echo ".agents"; }
FUNCTIONS_EOF

  # init.sh sources DEV_BOT_ROOT/src/_shared/functions.sh — stub it too.
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cp "${SANDBOX_DIR}/functions.sh" "${SANDBOX_DIR}/src/_shared/functions.sh"

  mkdir -p "${SANDBOX_DIR}/.claude"
}

_run_flat() {
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  set -- "${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/init.sh"
  _link_claude_skills_flat "${SANDBOX_DIR}"
}

# _add_user_skill <name>: create a real user skill dir (real SKILL.md).
_add_user_skill() {
  local name="$1"
  mkdir -p "${SANDBOX_DIR}/.claude/skills/${name}"
  printf '%s\n' "---" "name: ${name}" "---" "" "# ${name}" \
    > "${SANDBOX_DIR}/.claude/skills/${name}/SKILL.md"
}

# ── Preservation ────────────────────────────────────────────────────────────

@test "migrates a real user skill into .agents/skills and flattens it back" {
  _setup_sandbox
  _add_user_skill "my-skill"

  run _run_flat
  assert_success

  # original preserved in devbot_dir
  assert [ -f "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
  # flattened back so Claude Code still sees it
  assert [ -L "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md")" \
    == "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
}

@test "does not migrate dev-bot's own flat links (symlinked SKILL.md)" {
  _setup_sandbox
  # simulate a previous flat rebuild: symlinked SKILL.md pointing into the
  # sandbox DEV_BOT_ROOT (the same shape _link_skill_file creates)
  mkdir -p "${SANDBOX_DIR}/src/agentic/devbot/skills"
  printf '%s\n' "---" "name: devbot-skill" "---" "" "# Devbot" \
    > "${SANDBOX_DIR}/src/agentic/devbot/skills/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.claude/skills/devbot-skill"
  ln -s "${SANDBOX_DIR}/src/agentic/devbot/skills/SKILL.md" \
    "${SANDBOX_DIR}/.claude/skills/devbot-skill/SKILL.md"

  run _run_flat
  assert_success

  refute [ -e "${SANDBOX_DIR}/.agents/skills/devbot-skill" ]
}

@test "already-migrated skill is not duplicated on re-init" {
  _setup_sandbox
  # previous run: skill lives in .agents/skills (with the migration marker),
  # .claude/skills holds a flat link
  mkdir -p "${SANDBOX_DIR}/.agents/skills/my-skill"
  printf '%s\n' "---" "name: my-skill" "---" "" "# My skill" \
    > "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md"
  touch "${SANDBOX_DIR}/.agents/skills/my-skill/.devbot-migrated"
  mkdir -p "${SANDBOX_DIR}/.claude/skills/my-skill"
  ln -s "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" \
    "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md"

  run _run_flat
  assert_success

  # no .bkp duplicate of an already-migrated skill
  refute [ -e "${SANDBOX_DIR}/.agents/skills/my-skill.bkp" ]
  # flat link recreated
  assert [ -L "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md" ]
}

# ── Collision policy ────────────────────────────────────────────────────────

@test "collision: existing devbot_dir skill wins, user's kept as .bkp" {
  _setup_sandbox
  mkdir -p "${SANDBOX_DIR}/.agents/skills/taken"
  echo "devbot skill" > "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  _add_user_skill "taken"

  run _run_flat
  assert_success

  # devbot's version untouched
  run cat "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  assert_output "devbot skill"
  # user's preserved as .bkp
  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md" ]
}

# ── Review findings ─────────────────────────────────────────────────────────

@test "F1: tool-placed real dir in .agents/skills (no marker) is not flattened as user content" {
  _setup_sandbox
  # dev-bot's own skill source under the sandbox src/ tree (step 3 flat-links it)
  mkdir -p "${SANDBOX_DIR}/src/agentic/graphify/skills"
  printf '%s\n' "---" "name: graphify" "---" "" "# Graphify" \
    > "${SANDBOX_DIR}/src/agentic/graphify/skills/SKILL.md"
  # a real dir placed by a tool (graphify-style), NOT migrated by step 1
  mkdir -p "${SANDBOX_DIR}/.agents/skills/graphify"
  printf '%s\n' "---" "name: graphify" "---" "" "# Graphify" \
    > "${SANDBOX_DIR}/.agents/skills/graphify/SKILL.md"

  run _run_flat
  assert_success

  # no spurious .bkp duplicate of dev-bot's own skill
  refute [ -e "${SANDBOX_DIR}/.claude/skills/graphify.bkp" ]
  # dev-bot flat link intact
  assert [ -L "${SANDBOX_DIR}/.claude/skills/graphify/SKILL.md" ]
}

@test "F2: flat collision with existing .bkp re-suffixes instead of aborting" {
  _setup_sandbox
  # dev-bot skill source under the sandbox src/ tree; its frontmatter name
  # collides with the migrated user skills below
  mkdir -p "${SANDBOX_DIR}/src/agentic/graphify/skills"
  printf '%s\n' "---" "name: taken" "---" "" "# Devbot taken" \
    > "${SANDBOX_DIR}/src/agentic/graphify/skills/SKILL.md"
  # two marked user skills with the same frontmatter name: the second occupies
  # the .bkp flat slot, so the first must re-suffix to .bkp.bkp
  mkdir -p "${SANDBOX_DIR}/.agents/skills/taken"
  printf '%s\n' "---" "name: taken" "---" "" "# User taken" \
    > "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  touch "${SANDBOX_DIR}/.agents/skills/taken/.devbot-migrated"
  mkdir -p "${SANDBOX_DIR}/.agents/skills/taken.bkp"
  printf '%s\n' "---" "name: taken" "---" "" "# User taken bkp" \
    > "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md"
  touch "${SANDBOX_DIR}/.agents/skills/taken.bkp/.devbot-migrated"

  run _run_flat
  assert_success

  # both user skills flattened: devbot link at taken, users at .bkp and .bkp.bkp
  assert [ -L "${SANDBOX_DIR}/.claude/skills/taken.bkp/SKILL.md" ]
  assert [ -L "${SANDBOX_DIR}/.claude/skills/taken.bkp.bkp/SKILL.md" ]
}

@test "F3a: symlinked skill dir is dereferenced on migration and re-flattened" {
  _setup_sandbox
  # .claude/skills/my-skill is a symlink to a real dir elsewhere
  mkdir -p "${SANDBOX_DIR}/external/my-skill"
  printf '%s\n' "---" "name: my-skill" "---" "" "# My skill" \
    > "${SANDBOX_DIR}/external/my-skill/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.claude/skills"
  ln -s "${SANDBOX_DIR}/external/my-skill" "${SANDBOX_DIR}/.claude/skills/my-skill"

  run _run_flat
  assert_success

  # content copied as a REAL dir (dereferenced), not the symlink itself
  assert [ -d "${SANDBOX_DIR}/.agents/skills/my-skill" ]
  assert [ ! -L "${SANDBOX_DIR}/.agents/skills/my-skill" ]
  assert [ -f "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
  # flattened back so Claude Code sees it
  assert [ -L "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md" ]
}

@test "F3b: user skill with symlinked SKILL.md (not dev-bot's) is migrated with warning" {
  _setup_sandbox
  # real dir whose SKILL.md is a user-created symlink pointing OUTSIDE dev-bot
  # (external dir lives outside the sandbox DEV_BOT_ROOT)
  EXT_DIR="$(mktemp -d)"
  printf '%s\n' "---" "name: my-skill" "---" "" "# My skill" \
    > "${EXT_DIR}/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.claude/skills/my-skill"
  ln -s "${EXT_DIR}/SKILL.md" \
    "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md"

  run _run_flat
  assert_success

  # migrated (not dropped), with a warning
  assert_output --partial "WARN"
  assert [ -f "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
  rm -rf "${EXT_DIR}"
}

@test "F4: .bkp re-collision in step-1 migration re-suffixes instead of nesting/clobbering" {
  _setup_sandbox
  # devbot skill + existing .bkp backup + user skill with same name
  mkdir -p "${SANDBOX_DIR}/.agents/skills/taken"
  echo "devbot skill" > "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.agents/skills/taken.bkp"
  echo "old backup" > "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md"
  _add_user_skill "taken"

  run _run_flat
  assert_success

  # neither the devbot skill nor the old backup was clobbered
  run cat "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  assert_output "devbot skill"
  run cat "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md"
  assert_output "old backup"
  # new user skill re-suffixed, stored as a proper sibling (not nested)
  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken.bkp.bkp/SKILL.md" ]
  refute [ -d "${SANDBOX_DIR}/.agents/skills/taken.bkp/taken" ]
}
