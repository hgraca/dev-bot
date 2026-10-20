#!/usr/bin/env bats
# =============================================================================
# src/agentic/guards/tests/guards_tests.bats
# Tests for the guards module (manifest-declared hook + shared tool).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  MANIFEST="$MODULE_DIR/hooks.json"
  TOOL="$MODULE_DIR/tools/guards.ts"
  SKILL_FILE="$MODULE_DIR/skills/SKILL.md"
}

@test "hooks.json declares a blocking command.before guard hook" {
  run python3 -c "
import json
data = json.load(open('${MANIFEST}'))
hook = data['hooks'][0]
assert hook['event'] == 'command.before', hook
assert hook['blocking'] is True, hook
assert 'guards.ts' in hook['run'][1], hook
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

# The bash tool is not the only shell channel: a PTY session launches commands
# too. A matcher that omits the PTY tools silently drops every guard for
# long-running commands — precisely the traffic the shell strategy sends to a PTY.
@test "hooks.json guards every shell channel, not just bash" {
  run python3 -c "
import json
data = json.load(open('${MANIFEST}'))
tools = data['hooks'][0]['match']['tool']
for required in ('bash', 'shell', 'pty_spawn', 'pty_write'):
    assert required in tools, (required, tools)
print('CHANNELS:OK')
"
  assert_success
  grep -qF 'CHANNELS:OK' <<< "$output" || fail "guards matcher is missing a shell channel"
}

@test "shared guards tool exists" { [ -f "$TOOL" ]; }
@test "skill file exists" { [ -f "$SKILL_FILE" ]; }

@test "skill file has frontmatter" {
  run head -1 "$SKILL_FILE"
  assert_output --partial "---"
}

# ── Matching semantics (anchored per command segment) ──────────────────────────
# Tested against the DIST configs, never the runtime .devbot.{global,project}.jsonc:
# both runtime files are gitignored and machine-local, so a fresh checkout has
# neither and every one of these tests silently saw `{"blocked":false}` — a
# missing config loads no guards and the assertion "no output" still passed. The
# dists ship the same rules and are tracked, so the contract is hermetic.

@test "guards block a direct dangerous invocation" {
  run bun run "$TOOL" --command "rm -rf /tmp/guards-direct" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards do NOT block a safe command whose TEXT contains the pattern" {
  run bun run "$TOOL" --command 'echo "rm -rf is just text here"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "guards still block the pattern after a shell operator" {
  run bun run "$TOOL" --command "echo hi && rm -rf /tmp/guards-op" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards still block a command-runner wrapping the pattern" {
  run bun run "$TOOL" --command 'bash -c "rm -rf /tmp/guards-wrap"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push wrapped in a command runner" {
  run bun run "$TOOL" --command 'bash -c "git push --force origin main"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push wrapped in env" {
  run bun run "$TOOL" --command 'env FOO=bar git push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards do not block a non-push git command mentioning a force push" {
  run bun run "$TOOL" --command 'git commit -m "fix push --force handling"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "guards block a force-push after git global options" {
  run bun run "$TOOL" --command 'git -C /tmp/worktree push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a quoted -C value" {
  run bun run "$TOOL" --command 'git -C "/tmp/worktree with spaces" push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a quoted -c value" {
  run bun run "$TOOL" --command 'git -c "user.name=Jane Doe" push --force' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a mixed quoted option value" {
  run bun run "$TOOL" --command 'git -c user.name="Jane Doe" push --force' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a quoted generic option value" {
  run bun run "$TOOL" --command 'git --foo="a b" push --force' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards do not block a grep argument mentioning a force push" {
  run bun run "$TOOL" --command 'git log --grep="push --force"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "guards block a force-push with a quoted option name" {
  run bun run "$TOOL" --command 'git "-C" /tmp/worktree push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a quoted long option name" {
  run bun run "$TOOL" --command 'git "--no-pager" push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a double-quoted push subcommand" {
  run bun run "$TOOL" --command 'git "push" --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a single-quoted push subcommand" {
  run bun run "$TOOL" --command "git 'push' --force-with-lease origin main" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with escaped quotes in an option value" {
  run bun run "$TOOL" --command 'git -c user.name="A\" B" push --force' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a space-separated --git-dir" {
  run bun run "$TOOL" --command 'git --git-dir /tmp/repo/.git push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards block a force-push with a space-separated --work-tree" {
  run bun run "$TOOL" --command 'git --work-tree /tmp/repo push --force origin main' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "guards stay fast on repeated value-taking options" {
  local cmd="git"
  local i
  for i in $(seq 1 40); do
    cmd+=" --git-dir /tmp/repo/.git"
  done
  cmd+=" status"

  run bun run "$TOOL" --command "$cmd" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"

  assert_output --partial '"blocked":false'
}

@test "guards stay fast on repeated long options" {
  local cmd="git"
  local i
  for i in $(seq 1 40); do
    cmd+=" --no-pager"
  done
  cmd+=" status"

  run bun run "$TOOL" --command "$cmd" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"

  assert_output --partial '"blocked":false'
}

@test "guards stay fast on mixed quoted options" {
  local cmd="git"
  local i
  for i in $(seq 1 40); do
    cmd+=' -c user.name="a b"'
  done
  cmd+=" status"

  run bun run "$TOOL" --command "$cmd" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"

  assert_output --partial '"blocked":false'
}

@test "guards do not block a commit with global options and a push in its message" {
  run bun run "$TOOL" --command 'git -C /tmp/worktree commit -m "fix push --force handling"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "guards do not block a commit with a -c option and a push in its message" {
  run bun run "$TOOL" --command 'git -c "user.name=Jane Doe" commit -m "fix push --force handling"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "guards stay fast on repeated -C options" {
  local cmd="git"
  local i
  for i in $(seq 1 40); do
    cmd+=" -C -C"
  done
  cmd+=" status"

  run bun run "$TOOL" --command "$cmd" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"

  assert_output --partial '"blocked":false'
}

@test "guards stay fast on a long non-push git command" {
  local cmd="git"
  local i
  for i in $(seq 1 40); do
    cmd+=' -c "a=b"'
  done
  cmd+=" status"

  run bun run "$TOOL" --command "$cmd" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"

  assert_output --partial '"blocked":false'
}

@test "guards still block command substitution containing the pattern" {
  run bun run "$TOOL" --command 'echo \$(rm -rf /tmp/guards-sub)' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

# ── Shipped force-push guard ─────────────────────────────────────────────────
# The engine anchors ordinary command segments itself and deliberately matches
# command-runner arguments unanchored (guards.ts). The shipped rule must not
# embed a command-position anchor, or a wrapped force-push slips through.

@test "shipped guards block a force-push wrapped in bash -c" {
  run bun run "$TOOL" --command 'bash -c "git push --force origin topic"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a force-push wrapped in env" {
  run bun run "$TOOL" --command "env git push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a force-push with intervening git options" {
  run bun run "$TOOL" --command "git -C /tmp/repo push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a force-push with a quoted -C value" {
  run bun run "$TOOL" --command 'git -C "/tmp/my repo" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a force-push with a quoted -c value" {
  run bun run "$TOOL" --command 'git -c user.name="Dev Bot" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached -C value" {
  run bun run "$TOOL" --command "git -C. push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached -C path" {
  run bun run "$TOOL" --command "git -C/tmp/repo push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block --config-env with a separate value" {
  run bun run "$TOOL" --command "git --config-env core.sshCommand=GIT_SSH_COMMAND push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached quoted -C value" {
  run bun run "$TOOL" --command 'git -C"/tmp/my repo" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached quoted -c value" {
  run bun run "$TOOL" --command 'git -cuser.name="Dev Bot" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an escaped-space -C value" {
  run bun run "$TOOL" --command 'git -C /tmp/my\ repo push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached escaped-space -C value" {
  run bun run "$TOOL" --command 'git -C/tmp/my\ repo push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a double-quoted push subcommand" {
  run bun run "$TOOL" --command 'git "push" --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a single-quoted push subcommand" {
  run bun run "$TOOL" --command "git 'push' --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted -C option name" {
  run bun run "$TOOL" --command 'git "-C" /tmp/repo push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a single-quoted -C option name" {
  run bun run "$TOOL" --command "git '-C' /tmp/repo push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted attached -C option" {
  run bun run "$TOOL" --command 'git "-C/tmp/repo" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted attached -C value with a space" {
  run bun run "$TOOL" --command 'git "-C/tmp/my repo" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block equals-valued --git-dir" {
  run bun run "$TOOL" --command "git --git-dir=/tmp/repo/.git push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block equals-valued --work-tree" {
  run bun run "$TOOL" --command "git --work-tree=/tmp/work push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block equals-valued --namespace" {
  run bun run "$TOOL" --command "git --namespace=refs/heads/x push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block equals-valued --config-env" {
  run bun run "$TOOL" --command "git --config-env=core.sshCommand=GIT_SSH_COMMAND push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an inline alias expanding to a force-push" {
  run bun run "$TOOL" --command "git -c alias.publish='push --force' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an attached inline force-push alias" {
  run bun run "$TOOL" --command "git -calias.publish='push --force' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards match an uppercase alias section" {
  run bun run "$TOOL" --command "git -c ALIAS.publish='push --force' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a hyphenated alias name" {
  run bun run "$TOOL" --command "git -c alias.force-push='push --force' force-push origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a dotted alias name" {
  run bun run "$TOOL" --command "git -c alias.force.push='push --force' force.push origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a read-only alias definition" {
  run bun run "$TOOL" --command "git -c alias.audit='log --grep=push --grep=--force' audit" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards do NOT block a read-only grep for alias text" {
  run bun run "$TOOL" --command "git grep -c alias.publish" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped guards do NOT block a -C path starting with alias" {
  run bun run "$TOOL" --command "git -Calias.publish status" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped guards block a force flag followed by a command substitution" {
  run bun run "$TOOL" --command "git push --force\$(printf '') origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an ANSI-C quoted subcommand" {
  run bun run "$TOOL" --command "git \$'push' --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an unresolved expansion in the option prefix" {
  run bun run "$TOOL" --command 'opts=-C; git "$opts" /tmp/repo push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "global guards block a backtick substitution in the option prefix" {
  run bun run "$TOOL" --command 'git -C `git rev-parse --show-toplevel` push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config /dev/null
  assert_output --partial '"blocked":true'
}

@test "project guards block a backtick substitution in the option prefix" {
  run bun run "$TOOL" --command 'git -C `git rev-parse --show-toplevel` push --force origin topic' --global-config /dev/null --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards complete quickly on NBSP-joined options" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local nbsp=$'\xc2\xa0'
  local payload="git "
  local i
  for i in {1..24}; do payload+="${nbsp}-Cfoo"; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards complete quickly on repeated expansions" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git"
  local i
  for i in {1..44}; do payload+=" \$opts"; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards complete quickly on mixed expansion tokens" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git"
  local i
  for i in {1..24}; do payload+=" \$opts --no-pager"; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards block a force-with-lease alias value" {
  run bun run "$TOOL" --command "git -c alias.publish='push --force-with-lease=refs/heads/topic' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards do NOT block literal alias text in a quoted argument" {
  run bun run "$TOOL" --command "echo -c 'alias.publish=push --force'" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "a config without the alias rule does not block literal alias text" {
  local cfg
  cfg="$(mktemp)"
  cat > "$cfg" <<'JSONC'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked" } ] }
JSONC
  run bun run "$TOOL" --command "echo -c 'alias.publish=push --force'" --global-config "$cfg" --project-config "$cfg"
  rm -f "$cfg"
  assert_output --partial '"blocked":false'
}

@test "shipped guards block a quoted push despite an alias named push" {
  run bun run "$TOOL" --command 'git -c alias.push=status "push" --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted push despite an alias named git" {
  run bun run "$TOOL" --command 'git -c alias.git=status "push" --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block any inline alias" {
  run bun run "$TOOL" --command "git -c alias.st=status st" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a shell-body alias" {
  run bun run "$TOOL" --command "git -c alias.publish='! git push --force' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a config-quoted alias value" {
  run bun run "$TOOL" --command "git -c 'alias.publish=\"push\" --force' publish origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a recursive alias definition quickly" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git -c alias.a='"
  local i
  for i in {1..100}; do payload+="a "; done
  payload+="' a"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a Unicode-space path" {
  local nbsp=$'\xc2\xa0'
  run bun run "$TOOL" --command "git -C /tmp/my${nbsp}repo push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "custom raw rule still matches quoted argument values" {
  local cfg
  cfg="$(mktemp)"
  cat > "$cfg" <<'JSONC'
{ "guards": [ { "regex": "curl .*Authorization: Bearer", "message": "no tokens" } ] }
JSONC
  run bun run "$TOOL" --command 'curl -H "Authorization: Bearer test-token" https://example.test' --global-config "$cfg" --project-config "$cfg"
  rm -f "$cfg"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block escaped literal quotes in a value" {
  run bun run "$TOOL" --command 'git -c user.name=\"-foo\" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a single-quoted value starting with a dash" {
  run bun run "$TOOL" --command "git -C '-repo\\' push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block an empty -C value" {
  run bun run "$TOOL" --command 'git -C "" push --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted subcommand in a wrapper vector" {
  run bun run "$TOOL" --command 'env git "push" --force origin topic' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a quoted subcommand in an embedded shell string" {
  run bun run "$TOOL" --command 'bash -c "git '\''push'\'' --force origin topic"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a trailing backslash in single quotes" {
  run bun run "$TOOL" --command "git -c 'user.name=Dev\\' push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped guards block a single-quoted backslash value" {
  run bun run "$TOOL" --command "git -c core.commentChar='\\' push --force origin topic" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

# The value matcher's alternatives must stay disjoint: overlapping token
# alternatives made the guard backtrack exponentially on non-push input.
@test "shipped guards complete quickly on concatenated quoted fragments" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload='git -c user.name='
  local i
  for i in {1..20}; do payload+='"ab"'; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards complete quickly on repeated option tokens" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git"
  local i
  for i in {1..16}; do payload+=' -c core.quotePath="false"'; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards complete quickly on repeated attached -C options" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git"
  local i
  for i in {1..24}; do payload+=" -Cfoo"; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards complete quickly on repeated long options" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not available"
  local payload="git"
  local i
  for i in {1..44}; do payload+=" --git-dir"; done
  payload+=" status"

  run timeout 5 bun run "$TOOL" --command "$payload" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
}

@test "shipped guards do NOT block prose mentioning a force-push" {
  run bun run "$TOOL" --command 'echo "git push --force is prohibited"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped guards do NOT block a commit message mentioning a force-push" {
  run bun run "$TOOL" --command 'git commit -m "docs: explain push --force"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped guards do NOT block a log grep mentioning a force-push" {
  run bun run "$TOOL" --command 'git log --grep="push --force"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

# ── Shipped qmd guard (ADR 20260913072905-qmd-bm25-only-no-model-downloads) ──
# qmd is BM25-only and not agent-invokable; the shipped global config blocks the
# CLI. Tested against the DIST config — the live .devbot.global.jsonc is
# machine-local and reconciled from dist on update.

@test "shipped global guards block a direct qmd invocation" {
  run bun run "$TOOL" --command "qmd embed" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped global guards block qmd after a shell operator" {
  run bun run "$TOOL" --command "cd .agents && qmd update" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

@test "shipped global guards do NOT block harmless text mentioning qmd" {
  run bun run "$TOOL" --command 'echo "qmd is not agent-invokable"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped global guards do NOT block a glob mentioning qmd" {
  # A runner segment (find) matches UNANCHORED, so the old \bqmd\b blocked
  # `find … -name '*qmd*'` — a harmless search. The pattern must match qmd as a
  # command, not as a substring of an argument (audit-69 NOTE-7).
  run bun run "$TOOL" --command "find . -name '*qmd*'" --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":false'
}

@test "shipped global guards block qmd wrapped in a command runner" {
  run bun run "$TOOL" --command 'bash -c "qmd update"' --global-config "$TEST_DIR/../../../../.devbot.global.dist.jsonc" --project-config "$TEST_DIR/../../../../.devbot.project.dist.jsonc"
  assert_output --partial '"blocked":true'
}

# ── Dist config consistency ───────────────────────────────────────────────────
# The two dist configs ship together and the runtime merges project-first then
# global, so a regex present in both with different messages makes the reported
# advice depend on which file won — the user is told "requires approval" in one
# project and "is blocked" in another. They must agree (audit-69 NOTE-7).
@test "both dist configs declare the same message for a shared guard regex" {
  run python3 -c "
import json, subprocess
read_jsonc = '${TEST_DIR}/../../../../src/_shared/read_jsonc.py'
def guards(path):
    out = subprocess.check_output(['python3', read_jsonc, path])
    return {g['regex']: g['message'] for g in json.loads(out).get('guards', [])}
project = guards('${TEST_DIR}/../../../../.devbot.project.dist.jsonc')
global_dist = guards('${TEST_DIR}/../../../../.devbot.global.dist.jsonc')
for regex, message in project.items():
    assert global_dist.get(regex) == message, f'{regex}: project={message!r} global={global_dist.get(regex)!r}'
print('GUARDS:CONSISTENT')
"
  assert_success
  grep -qF 'GUARDS:CONSISTENT' <<< "$output" || fail "dist guard messages diverge"
}
