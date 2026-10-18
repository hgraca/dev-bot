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
