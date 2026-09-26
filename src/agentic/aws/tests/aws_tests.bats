#!/usr/bin/env bats
# =============================================================================
# src/agentic/aws/tests/aws_tests.bats
# Tests for the AWS module's deterministic logic:
#   - set_jsonc_key.py (comment-preserving config writes)
#   - aws-mcp-proxy.sh (region precedence)
#   - install.sh (non-interactive region resolution + config write)
#   - up.sh (auth guard)
#   - init.sh (launcher symlink + rules wiring)
# Network/auth steps are exercised only via fake binaries on PATH.
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  REPO_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"

  SET_JSONC="$REPO_ROOT/src/_shared/set_jsonc_key.py"
  READ_JSONC="$REPO_ROOT/src/_shared/read_jsonc.py"
  TRANSLATE="$REPO_ROOT/src/_shared/mcp_translate.py"
  LAUNCHER="$MODULE_DIR/tools/aws-mcp-proxy.sh"
  INSTALL="$MODULE_DIR/install.sh"
  UP="$MODULE_DIR/up.sh"
  INIT="$MODULE_DIR/init.sh"

  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

assert_json_eq() {
  # Compare two JSON blobs key-order-insensitively.
  assert_equal "$(jq -S . <<<"$1")" "$(jq -S . <<<"$2")"
}

# ── MCP manifest (canonical, harness-agnostic) ────────────────────────────────

@test "mcp.json declares one canonical aws-mcp stdio server, log-redirected" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['aws-mcp']
assert m['type'] == 'stdio', m
assert m['enabled'] is False, m
cmd = m['command']
assert cmd[0] == 'bash' and cmd[1] == '-c', cmd
assert '{harness-dir}/aws-mcp-proxy.sh' in cmd[2], cmd
assert '2>>.agents/logs/aws-mcp.log' in cmd[2], cmd
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "MCP integration is a single canonical mcp.json, not a per-harness pair" {
  [ -f "${MODULE_DIR}/mcp.json" ]
  [ ! -f "${MODULE_DIR}/mcp.opencode.json" ]
  [ ! -f "${MODULE_DIR}/mcp.claudecode.json" ]
}

@test "translates to opencode as a local server, disabled" {
  run python3 "$TRANSLATE" "${MODULE_DIR}/mcp.json" opencode
  assert_success
  assert_json_eq "$output" \
    '{"aws-mcp": {"type": "local", "command": ["bash", "-c", "mkdir -p .agents/logs && exec bash .opencode/aws-mcp-proxy.sh 2>>.agents/logs/aws-mcp.log"], "enabled": false}}'
}

@test "translates to claudecode as stdio (enabled dropped)" {
  run python3 "$TRANSLATE" "${MODULE_DIR}/mcp.json" claudecode
  assert_success
  assert_json_eq "$output" \
    '{"aws-mcp": {"type": "stdio", "command": "bash", "args": ["-c", "mkdir -p .agents/logs && exec bash .claude/aws-mcp-proxy.sh 2>>.agents/logs/aws-mcp.log"]}}'
}

# ── set_jsonc_key.py ───────────────────────────────────────────────────────────

@test "set_jsonc_key: inserts a new top-level key, preserving comments" {
  cat > "$TMP/cfg.jsonc" <<'EOF'
{
  // keep me
  "existing": true
}
EOF
  run python3 "$SET_JSONC" "$TMP/cfg.jsonc" aws_region '"us-east-1"'
  assert_success
  assert_output "SET"

  run python3 "$READ_JSONC" "$TMP/cfg.jsonc" aws_region
  assert_output "us-east-1"

  run grep -c '// keep me' "$TMP/cfg.jsonc"
  assert_output "1"
}

@test "set_jsonc_key: replaces an existing top-level key" {
  echo '{"aws_region":"us-east-1"}' > "$TMP/cfg.jsonc"
  run python3 "$SET_JSONC" "$TMP/cfg.jsonc" aws_region '"eu-west-1"'
  assert_success
  run python3 "$READ_JSONC" "$TMP/cfg.jsonc" aws_region
  assert_output "eu-west-1"
}

@test "set_jsonc_key: idempotent — UNCHANGED when value equal" {
  echo '{"aws_region":"us-east-1"}' > "$TMP/cfg.jsonc"
  run python3 "$SET_JSONC" "$TMP/cfg.jsonc" aws_region '"us-east-1"'
  assert_success
  assert_output "UNCHANGED"
}

@test "set_jsonc_key: does not touch a nested key of the same name" {
  cat > "$TMP/cfg.jsonc" <<'EOF'
{ "nested": { "aws_region": "keep-nested" } }
EOF
  run python3 "$SET_JSONC" "$TMP/cfg.jsonc" aws_region '"top-level"'
  assert_success
  run python3 "$READ_JSONC" "$TMP/cfg.jsonc" nested aws_region
  assert_output "keep-nested"
  run python3 "$READ_JSONC" "$TMP/cfg.jsonc" aws_region
  assert_output "top-level"
}

# ── aws-mcp-proxy.sh profile + region precedence ──────────────────────────────

_fake_uvx() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/uvx" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
EOF
  chmod +x "$TMP/bin/uvx"
}

@test "launcher: AWS_PROFILE env wins over configs" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_profile":"proj-ro"}' > "$TMP/proj/.devbot.project.jsonc"
  echo '{"aws_profile":"glob-ro"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_PROFILE=env-ro PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "--profile env-ro"
}

@test "launcher: project profile beats global" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_profile":"proj-ro"}' > "$TMP/proj/.devbot.project.jsonc"
  echo '{"aws_profile":"glob-ro"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "--profile proj-ro"
}

@test "launcher: global profile used when project and env are unset" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{}' > "$TMP/proj/.devbot.project.jsonc"
  echo '{"aws_profile":"glob-ro"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "--profile glob-ro"
}

@test "launcher: fails loudly when no profile resolves" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_failure
  assert_output --partial "no AWS profile resolved"
}

@test "launcher: pins --profile, never --skip-auth, keeps INSTALL_SOURCE metadata" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_profile":"ro"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "--profile ro"
  assert_output --partial "INSTALL_SOURCE=agent-toolkit-core"
  refute_output --partial "--skip-auth"
}

@test "launcher: warns when AWS_MCP_PROXY_PROFILES would override the pin" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_profile":"ro"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_MCP_PROXY_PROFILES="ro admin" \
    PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "AWS_MCP_PROXY_PROFILES is set and takes precedence"
}

@test "launcher: AWS_REGION env wins over everything" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_region":"eu-central-1"}' > "$TMP/proj/.devbot.project.jsonc"
  echo '{}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_PROFILE=ro AWS_REGION=ap-south-1 \
    PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "AWS_REGION=ap-south-1"
}

@test "launcher: project config region beats global + default" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{"aws_region":"eu-central-1"}' > "$TMP/proj/.devbot.project.jsonc"
  echo '{"aws_region":"us-west-2"}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_PROFILE=ro PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "AWS_REGION=eu-central-1"
}

@test "launcher: falls back to default us-east-1 when nothing set" {
  _fake_uvx
  mkdir -p "$TMP/proj" "$TMP/root"
  echo '{}' > "$TMP/root/.devbot.global.jsonc"
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_PROFILE=ro PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_success
  assert_output --partial "AWS_REGION=us-east-1"
}

# ── install.sh (non-interactive) ──────────────────────────────────────────────

@test "install.sh: writes default region to global config when non-interactive" {
  mkdir -p "$TMP/bin" "$TMP/root" "$TMP/home"
  echo '{"project_name":"demo"}' > "$TMP/root/.devbot.global.jsonc"

  for cmd in uv unzip; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/$cmd"
    chmod +x "$TMP/bin/$cmd"
  done
  cat > "$TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TMP/bin/aws"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do [[ "${args[$i]}" == "-o" ]] && out="${args[$((i+1))]}"; done
[[ -n "$out" ]] && echo "# rules" > "$out"
exit 0
EOF
  chmod +x "$TMP/bin/curl"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$INSTALL"
  assert_success

  run python3 "$READ_JSONC" "$TMP/root/.devbot.global.jsonc" aws_region
  assert_output "us-east-1"
}

# ── up.sh ─────────────────────────────────────────────────────────────────────

@test "up.sh: reports valid credentials when authenticated" {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TMP/bin/aws"
  run env PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "credentials valid"
}

@test "up.sh: warns (does not fail) when unauthenticated and non-TTY" {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
exit 255
EOF
  chmod +x "$TMP/bin/aws"
  run env PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "aws login"
}

# ── init.sh ───────────────────────────────────────────────────────────────────

@test "init.sh: symlinks launcher and copies rules into memory vault" {
  mkdir -p "$TMP/proj" "$TMP/root/storage/aws/rules"
  echo '{}' > "$TMP/root/.devbot.global.jsonc"
  echo "# aws rules" > "$TMP/root/storage/aws/rules/aws-agent-rules.md"

  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  assert [ -L "$TMP/proj/.opencode/aws-mcp-proxy.sh" ]
  assert [ -L "$TMP/proj/.claude/aws-mcp-proxy.sh" ]
  run cat "$TMP/proj/.agents/memory/active/aws-agent-rules.md"
  assert_output "# aws rules"
  run bash "$INIT" "$TMP/proj"
  assert_output --partial 'aws_region'
}
