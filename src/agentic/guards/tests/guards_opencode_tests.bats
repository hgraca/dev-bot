#!/usr/bin/env bats

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

# ── opencode hook: tool.execute.before ────────────────────────────────────────

@test "opencode hook: blocks rm -rf via tool.execute.before event" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  mkdir -p "${tmpdir}/.agents"
  cat > "${tmpdir}/.devbot.project.jsonc" << 'EOF'
{ "devbot_dir": ".agents" }
EOF
  cat > "${tmpdir}/.agents/devbot.jsonc" << 'EOF'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked" } ] }
EOF

  run bun -e "
    import { GuardsPlugin } from '${MODULE_DIR}/hooks/opencode/on-tool_execute_before-guards.ts';
    const plugin = await GuardsPlugin({ directory: '${tmpdir}' });
    const handler = plugin['tool.execute.before'];
    try {
      await handler({ tool: 'bash' }, { args: { command: 'rm -rf /tmp/foo' } });
      console.log('RESULT:NOT_BLOCKED');
    } catch(e) {
      console.log('RESULT:[BLOCKED]');
      console.log('MESSAGE:' + e.message);
    }
  "
  assert_success
  grep -qF 'RESULT:[BLOCKED]' <<< "$output" || fail "expected [BLOCKED] (got: $output)"
  grep -qF 'rm -rf is blocked' <<< "$output" || fail "expected guard message"
  rm -rf "$tmpdir"
}

@test "opencode hook: allows safe commands via tool.execute.before event" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  mkdir -p "${tmpdir}/.agents"
  cat > "${tmpdir}/.devbot.project.jsonc" << 'EOF'
{ "devbot_dir": ".agents" }
EOF
  cat > "${tmpdir}/.agents/devbot.jsonc" << 'EOF'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked" } ] }
EOF

  run bun -e "
    import { GuardsPlugin } from '${MODULE_DIR}/hooks/opencode/on-tool_execute_before-guards.ts';
    const plugin = await GuardsPlugin({ directory: '${tmpdir}' });
    const handler = plugin['tool.execute.before'];
    try {
      await handler({ tool: 'bash' }, { args: { command: 'ls -la' } });
      console.log('RESULT:NOT_BLOCKED');
    } catch(e) {
      console.log('RESULT:[BLOCKED]');
      console.log('MESSAGE:' + e.message);
    }
  "
  assert_success
  grep -qF 'RESULT:NOT_BLOCKED' <<< "$output" || fail "expected NOT_BLOCKED (got: $output)"
  rm -rf "$tmpdir"
}
