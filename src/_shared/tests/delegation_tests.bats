#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/delegation_tests.bats
# Tests for _harness_delegate_type():
#   - files, symlinks AND directories migrate into devbot_dir
#   - collision policy: existing dest keeps its name (devbot wins), the
#     user's artifact is preserved as <name>.bkp — nothing is clobbered or lost
#   - already-delegated dirs are skipped (idempotent)
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  # Real shared library (reader resolves against PROJECT_ROOT); project config
  # pins devbot_dir to .agents so tests are hermetic (no global config coupling).
  export DEV_BOT_ROOT="${PROJECT_ROOT}"
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "devbot_dir": ".agents"
}
JSONC_EOF
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# shellcheck source=../functions.sh
_source_lib() {
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

# _delegate <type> [project_dir]: delegate one type of a .claude dir.
_delegate() {
  local type="$1"
  local project_dir="${2:-${SANDBOX_DIR}}"
  run _harness_delegate_type "${project_dir}/.claude" "${project_dir}" "${type}"
}

# ── Happy path: files, dirs, symlinks ───────────────────────────────────────

@test "migrates a file into devbot_dir and symlinks the harness dir" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/agents"
  echo "# user agent" > "${SANDBOX_DIR}/.claude/agents/user-agent.md"

  _delegate agents

  assert_success
  assert [ -f "${SANDBOX_DIR}/.agents/agents/user-agent.md" ]
  assert [ -L "${SANDBOX_DIR}/.claude/agents" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.claude/agents")" == "../.agents/agents" ]
  # the file is now reachable through the delegation symlink
  assert [ -f "${SANDBOX_DIR}/.claude/agents/user-agent.md" ]
}

@test "migrates a directory (skill) into devbot_dir" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/skills/my-skill"
  echo "name: my-skill" > "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md"

  _delegate skills

  assert_success
  assert [ -f "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
  assert [ -L "${SANDBOX_DIR}/.claude/skills" ]
}

@test "migrates a symlink into devbot_dir preserving its target" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/commands" "${SANDBOX_DIR}/real-dir"
  echo "# cmd" > "${SANDBOX_DIR}/real-dir/my-cmd.sh"
  ln -s "${SANDBOX_DIR}/real-dir" "${SANDBOX_DIR}/.claude/commands/my-cmd"

  _delegate commands

  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/commands/my-cmd" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/commands/my-cmd")" == "${SANDBOX_DIR}/real-dir" ]
}

# ── Collision policy: devbot wins, user's preserved as .bkp ─────────────────

@test "file collision: existing dest keeps its name, user's saved as .bkp" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/agents" "${SANDBOX_DIR}/.agents/agents"
  echo "devbot content" > "${SANDBOX_DIR}/.agents/agents/foo.md"
  echo "user content" > "${SANDBOX_DIR}/.claude/agents/foo.md"

  _delegate agents

  assert_success
  # devbot's artifact untouched
  assert [ -f "${SANDBOX_DIR}/.agents/agents/foo.md" ]
  run cat "${SANDBOX_DIR}/.agents/agents/foo.md"
  assert_output "devbot content"
  # user's artifact preserved as .bkp, not lost
  assert [ -f "${SANDBOX_DIR}/.agents/agents/foo.md.bkp" ]
  run cat "${SANDBOX_DIR}/.agents/agents/foo.md.bkp"
  assert_output "user content"
}

@test "dir collision: user's directory saved as .bkp" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/skills/taken" "${SANDBOX_DIR}/.agents/skills/taken"
  echo "devbot skill" > "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  echo "user skill" > "${SANDBOX_DIR}/.claude/skills/taken/SKILL.md"

  _delegate skills

  assert_success
  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md" ]
  run cat "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  assert_output "devbot skill"
  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md" ]
  run cat "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md"
  assert_output "user skill"
}

@test "symlink collision with different target: user's saved as .bkp" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/agents" "${SANDBOX_DIR}/.agents/agents" \
           "${SANDBOX_DIR}/src-a" "${SANDBOX_DIR}/src-b"
  ln -s "${SANDBOX_DIR}/src-a" "${SANDBOX_DIR}/.agents/agents/dup"
  ln -s "${SANDBOX_DIR}/src-b" "${SANDBOX_DIR}/.claude/agents/dup"

  _delegate agents

  assert_success
  # devbot's symlink untouched
  assert [ -L "${SANDBOX_DIR}/.agents/agents/dup" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/agents/dup")" == "${SANDBOX_DIR}/src-a" ]
  # user's symlink preserved as .bkp
  assert [ -L "${SANDBOX_DIR}/.agents/agents/dup.bkp" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/agents/dup.bkp")" == "${SANDBOX_DIR}/src-b" ]
}

@test "symlink collision with same target: skipped (already migrated)" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/agents" "${SANDBOX_DIR}/.agents/agents" "${SANDBOX_DIR}/src"
  ln -s "${SANDBOX_DIR}/src" "${SANDBOX_DIR}/.agents/agents/dup"
  ln -s "${SANDBOX_DIR}/src" "${SANDBOX_DIR}/.claude/agents/dup"

  _delegate agents

  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/agents/dup" ]
  assert [ ! -e "${SANDBOX_DIR}/.agents/agents/dup.bkp" ]
}

# ── Idempotency ─────────────────────────────────────────────────────────────

@test "already delegated: skipped, no duplicate work" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}/.agents/agents"
  ln -s "../.agents/agents" "${SANDBOX_DIR}/.claude/agents"

  _delegate agents

  assert_success
  assert_output --partial "already delegated"
  assert [ -L "${SANDBOX_DIR}/.claude/agents" ]
}

# ── Migrate-only mode (opencode skills when devbot_dir is .agents) ──────────

@test "migrate-only: content moves to devbot_dir, NO delegation symlink" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/skills/my-skill"
  echo "name: my-skill" > "${SANDBOX_DIR}/.claude/skills/my-skill/SKILL.md"

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills" "true"
  assert_success

  # content migrated
  assert [ -f "${SANDBOX_DIR}/.agents/skills/my-skill/SKILL.md" ]
  # no symlink created — .claude/skills is gone entirely
  refute [ -e "${SANDBOX_DIR}/.claude/skills" ]
}

@test "migrate-only: absent dir is skipped, no symlink created" {
  _source_lib

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills" "true"
  assert_success

  refute [ -e "${SANDBOX_DIR}/.claude/skills" ]
  refute [ -e "${SANDBOX_DIR}/.agents/skills" ]
}

@test "F6: migrate-only with absent dir does not claim a migration happened" {
  _source_lib

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills" "true"
  assert_success
  refute_output --partial "content migrated"
}

@test "migrate-only: collision keeps devbot's artifact, user's stored as .bkp" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/skills/taken" "${SANDBOX_DIR}/.agents/skills/taken"
  echo "devbot skill" > "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  echo "user skill" > "${SANDBOX_DIR}/.claude/skills/taken/SKILL.md"

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills" "true"
  assert_success

  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md" ]
  run cat "${SANDBOX_DIR}/.agents/skills/taken/SKILL.md"
  assert_output "devbot skill"
  assert [ -f "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md" ]
  run cat "${SANDBOX_DIR}/.agents/skills/taken.bkp/SKILL.md"
  assert_output "user skill"
  # no symlink
  refute [ -e "${SANDBOX_DIR}/.claude/skills" ]
}

@test "F4: .bkp re-collision re-suffixes instead of nesting/clobbering" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/.claude/agents" "${SANDBOX_DIR}/.agents/agents"
  echo "devbot agent" > "${SANDBOX_DIR}/.agents/agents/taken.md"
  echo "old backup" > "${SANDBOX_DIR}/.agents/agents/taken.md.bkp"
  echo "user agent" > "${SANDBOX_DIR}/.claude/agents/taken.md"

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "agents"
  assert_success

  # neither devbot's nor the old backup was clobbered
  run cat "${SANDBOX_DIR}/.agents/agents/taken.md"
  assert_output "devbot agent"
  run cat "${SANDBOX_DIR}/.agents/agents/taken.md.bkp"
  assert_output "old backup"
  # user's stored as re-suffixed sibling
  assert [ -f "${SANDBOX_DIR}/.agents/agents/taken.md.bkp.bkp" ]
  run cat "${SANDBOX_DIR}/.agents/agents/taken.md.bkp.bkp"
  assert_output "user agent"
}

@test "F5: wrong-target type-dir symlink is preserved, not destroyed (normal mode)" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/my-skills"
  echo "name: my-skill" > "${SANDBOX_DIR}/my-skills/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.claude"
  ln -s "${SANDBOX_DIR}/my-skills" "${SANDBOX_DIR}/.claude/skills"

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills"
  assert_success

  # the user's symlink pointer is preserved inside devbot_dir
  assert [ -L "${SANDBOX_DIR}/.agents/skills/my-skills" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/skills/my-skills")" == "${SANDBOX_DIR}/my-skills" ]
  # and the harness dir is still delegated
  assert [ -L "${SANDBOX_DIR}/.claude/skills" ]
}

@test "F5: wrong-target type-dir symlink is preserved, not destroyed (migrate-only)" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/my-skills"
  echo "name: my-skill" > "${SANDBOX_DIR}/my-skills/SKILL.md"
  mkdir -p "${SANDBOX_DIR}/.claude"
  ln -s "${SANDBOX_DIR}/my-skills" "${SANDBOX_DIR}/.claude/skills"

  run _harness_delegate_type "${SANDBOX_DIR}/.claude" "${SANDBOX_DIR}" "skills" "true"
  assert_success

  # pointer preserved under devbot_dir
  assert [ -L "${SANDBOX_DIR}/.agents/skills/my-skills" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/skills/my-skills")" == "${SANDBOX_DIR}/my-skills" ]
}
