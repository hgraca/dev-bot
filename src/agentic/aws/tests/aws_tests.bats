#!/usr/bin/env bats
# =============================================================================
# src/agentic/aws/tests/aws_tests.bats
# Tests for the AWS module:
#   - init.sh (per-connection dynamic manifests, prune/reconcile, launcher link)
#   - aws-mcp-proxy.sh (connection resolution: env XOR profile, region, account pin)
#   - install.sh / up.sh (non-interactive dependency setup + verify-only)
# Network/auth steps are exercised only via fake binaries on PATH.
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  REPO_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"

  READ_JSONC="$REPO_ROOT/src/_shared/read_jsonc.py"
  LAUNCHER="$MODULE_DIR/tools/aws-mcp-proxy.sh"
  INSTALL="$MODULE_DIR/install.sh"
  UP="$MODULE_DIR/up.sh"
  INIT="$MODULE_DIR/init.sh"

  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# A fake uvx that reports the argv AND the credential environment it inherited.
_fake_uvx() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/uvx" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
echo "KEY:${AWS_ACCESS_KEY_ID:-<unset>}"
echo "SECRET:${AWS_SECRET_ACCESS_KEY:-<unset>}"
echo "REGION:${AWS_REGION:-<unset>}"
echo "PROFILE:${AWS_PROFILE:-<unset>}"
echo "PROFILES:${AWS_MCP_PROXY_PROFILES:-<unset>}"
EOF
  chmod +x "$TMP/bin/uvx"
}

# A fake aws CLI that reports a fixed account for sts get-caller-identity and
# records the arguments it was called with, so a test can assert --profile
# actually reaches it.
_fake_aws_account() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/aws-argv.log"
if [[ "\${1:-} \${2:-}" == "sts get-caller-identity" ]]; then
  echo "$1"
  exit 0
fi
exit 1
EOF
  chmod +x "$TMP/bin/aws"
}

# ── init.sh — per-connection dynamic manifests ────────────────────────────────

_aws_seed_project() {
  mkdir -p "$TMP/proj" "$TMP/root/storage/aws/rules"
  echo '# aws rules' > "$TMP/root/storage/aws/rules/aws-agent-rules.md"
  cat > "$TMP/root/.devbot.global.jsonc" <<'EOF'
{
  "aws_connections": {
    "prod": { "region": "eu-central-1", "env": { "AWS_ACCESS_KEY_ID": "${PROD_KEY}" } },
    "dev":  { "region": "eu-west-1", "profile": "dev-ro" }
  }
}
EOF
  echo '{"aws_connections": ["prod", "dev"]}' > "$TMP/proj/.devbot.project.jsonc"
}

@test "init.sh: writes one manifest per selected connection and links the launcher" {
  _aws_seed_project
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  assert [ -L "$TMP/proj/.opencode/aws-mcp-proxy.sh" ]
  assert [ -L "$TMP/proj/.claude/aws-mcp-proxy.sh" ]
  assert [ -f "$TMP/proj/.opencode/aws-prod.mcp.json" ]
  assert [ -f "$TMP/proj/.opencode/aws-dev.mcp.json" ]
  assert [ -f "$TMP/proj/.claude/aws-prod.mcp.json" ]
}

@test "init.sh: the manifest invokes the launcher with the connection and no secret" {
  _aws_seed_project
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  run python3 -c "
import json
m = json.load(open('$TMP/proj/.opencode/aws-prod.mcp.json'))['aws-prod']
assert m['type'] == 'local', m
assert m['enabled'] is False, m
cmd = m['command']
assert cmd[:2] == ['bash', '-c'], cmd
assert 'aws-mcp-proxy.sh prod' in cmd[2], cmd
assert 'PROD_KEY' not in cmd[2], cmd  # secret-free: only the connection is named
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "init.sh: the claudecode manifest is stdio with the same command" {
  _aws_seed_project
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  run python3 -c "
import json
m = json.load(open('$TMP/proj/.claude/aws-prod.mcp.json'))['mcpServers']['aws-prod']
assert m['type'] == 'stdio', m
assert m['command'] == 'bash', m
assert m['args'][0] == '-c', m
assert 'aws-mcp-proxy.sh prod' in m['args'][1], m
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "init.sh: re-running is idempotent (manifests byte-identical)" {
  _aws_seed_project
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  before="$(cat "$TMP/proj/.opencode/aws-prod.mcp.json")"
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  after="$(cat "$TMP/proj/.opencode/aws-prod.mcp.json")"
  assert_equal "$before" "$after"
}

@test "init.sh: warns when a selected connection is not declared, and wires nothing for it" {
  _aws_seed_project
  echo '{"aws_connections": ["prod", "ghost"]}' > "$TMP/proj/.devbot.project.jsonc"
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success
  assert_output --partial "ghost"
  assert_output --partial "not declared"
  # A server that could not start must not be wired at all.
  assert [ ! -f "$TMP/proj/.opencode/aws-ghost.mcp.json" ]
  assert [ ! -f "$TMP/proj/.claude/aws-ghost.mcp.json" ]
  assert [ -f "$TMP/proj/.opencode/aws-prod.mcp.json" ]
}

@test "init.sh: prunes a deselected connection's manifests" {
  _aws_seed_project
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  assert [ -f "$TMP/proj/.opencode/aws-dev.mcp.json" ]

  echo '{"aws_connections": ["prod"]}' > "$TMP/proj/.devbot.project.jsonc"
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null

  assert [ -f "$TMP/proj/.opencode/aws-prod.mcp.json" ]
  assert [ ! -f "$TMP/proj/.opencode/aws-dev.mcp.json" ]
  assert [ ! -f "$TMP/proj/.claude/aws-dev.mcp.json" ]
}

@test "init.sh: copies the AWS agent rules into the memory vault" {
  _aws_seed_project
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success
  run cat "$TMP/proj/.agents/memory/active/aws-agent-rules.md"
  assert_output "# aws rules"
}

@test "init.sh: removes a deselected connection's key from opencode.jsonc" {
  _aws_seed_project
  cat > "$TMP/proj/opencode.jsonc" <<'EOF'
{
  "mcp": {
    "aws-prod": { "type": "local", "command": ["bash", "-c", "x"], "enabled": false },
    "aws-dev":  { "type": "local", "command": ["bash", "-c", "x"], "enabled": false },
    "other":    { "type": "local", "command": ["bash", "-c", "y"] }
  }
}
EOF
  echo '{"aws_connections": ["prod"]}' > "$TMP/proj/.devbot.project.jsonc"
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  run python3 -c "
import json
m = json.load(open('$TMP/proj/opencode.jsonc'))['mcp']
assert 'aws-prod' in m, m
assert 'aws-dev' not in m, m   # deselected -> key removed
assert 'other' in m, m         # not ours -> untouched
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "init.sh: leaves opencode.jsonc byte-identical across a re-init" {
  _aws_seed_project
  echo '{"mcp": {"aws-prod": {"type": "local", "command": ["bash", "-c", "x"], "enabled": false}}}' \
    > "$TMP/proj/opencode.jsonc"
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  before="$(cat "$TMP/proj/opencode.jsonc")"
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  after="$(cat "$TMP/proj/opencode.jsonc")"
  assert_equal "$before" "$after"
}

@test "init.sh: skips the claudecode manifest when that harness is disabled" {
  _aws_seed_project
  echo '{"aws_connections": ["prod"], "modules": {"claudecode": false}}' \
    > "$TMP/proj/.devbot.project.jsonc"
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success
  assert [ -f "$TMP/proj/.opencode/aws-prod.mcp.json" ]
  assert [ ! -f "$TMP/proj/.claude/aws-prod.mcp.json" ]
}

# ── aws-mcp-proxy.sh — connection resolution ──────────────────────────────────

_aws_global() {
  mkdir -p "$TMP/proj" "$TMP/root"
  cat > "$TMP/root/.devbot.global.jsonc"
}

@test "launcher: requires a connection argument" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_failure
  assert_output --partial "usage"
}

@test "launcher: rejects an undeclared connection" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" ghost
  assert_failure
  assert_output --partial "not declared"
}

@test "launcher: env form exports resolved keys, never on argv" {
  _fake_uvx
  _aws_global <<'EOF'
{
  "aws_connections": {
    "prod": {
      "region": "eu-central-1",
      "env": {
        "AWS_ACCESS_KEY_ID": "${PROD_KEY}",
        "AWS_SECRET_ACCESS_KEY": "literal-secret"
      }
    }
  }
}
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PROD_KEY=AKIAEXAMPLE PATH="$TMP/bin:/usr/bin:/bin" \
    bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "KEY:AKIAEXAMPLE"
  assert_output --partial "SECRET:literal-secret"
  assert_output --partial "REGION:eu-central-1"
  # A secret must never appear on the command line (argv is visible in `ps`).
  local args_line
  args_line="$(printf '%s\n' "$output" | grep '^ARGS:')"
  [[ "${args_line}" != *"AKIAEXAMPLE"* ]]
  [[ "${args_line}" != *"literal-secret"* ]]
}

@test "launcher: a literal env value never reaches a child's argv" {
  _fake_uvx
  # A python3 shim that records the argv of every child the launcher spawns.
  local real_python
  real_python="$(command -v python3)"
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/python3" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/argv.log"
exec "${real_python}" "\$@"
EOF
  chmod +x "$TMP/bin/python3"

  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "env": { "AWS_SECRET_ACCESS_KEY": "LITERALSECRET" } } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  # The value must reach the proxy...
  assert_output --partial "SECRET:LITERALSECRET"
  # ...but no child's argv may carry it (argv is world-readable in ps / /proc).
  run grep -c "LITERALSECRET" "$TMP/argv.log"
  assert_output "0"
}

@test "launcher: a missing \${VAR} refuses to start with nothing on stdout" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "env": { "AWS_ACCESS_KEY_ID": "${MISSING_KEY}" } } } }
EOF
  cd "$TMP/proj"
  run --separate-stderr env -u MISSING_KEY DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_failure
  # MCP speaks JSON-RPC on stdout: the diagnostic must be on stderr only.
  assert_equal "$output" ""
  [[ "$stderr" == *"resolves to nothing"* ]]
}

@test "launcher: profile form passes --profile and exports no keys" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "dev": { "region": "eu-west-1", "profile": "dev-ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" dev
  assert_success
  assert_output --partial "--profile dev-ro"
  assert_output --partial "KEY:<unset>"
}

@test "launcher: rejects a connection declaring both env and profile" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "both": { "region": "eu-west-1", "profile": "ro", "env": { "AWS_ACCESS_KEY_ID": "x" } } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" both
  assert_failure
  assert_output --partial "both env and profile"
}

@test "launcher: rejects a connection with neither env nor profile" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "empty": { "region": "eu-west-1" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" empty
  assert_failure
  assert_output --partial "neither env nor profile"
}

@test "launcher: account_id match proceeds" {
  _fake_uvx
  _fake_aws_account "123456789012"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "--profile ro"
}

@test "launcher: account_id mismatch refuses to start" {
  _fake_uvx
  _fake_aws_account "999999999999"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_failure
  assert_output --partial "expected '123456789012'"
}

@test "launcher: drops AWS_MCP_PROXY_PROFILES so it cannot defeat the pin" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_MCP_PROXY_PROFILES="ro admin" \
    PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "would let the agent switch profiles"
  # The variable must not survive into the proxy process.
  assert_output --partial "PROFILES:<unset>"
}

@test "launcher: region falls back to AWS_REGION when the connection omits it" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" AWS_REGION=ap-south-1 PATH="$TMP/bin:/usr/bin:/bin" \
    bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "REGION:ap-south-1"
}

@test "launcher: a region supplied through the repo .env is honoured" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "dev": { "profile": "dev-ro" } } }
EOF
  echo 'AWS_REGION=ap-south-1' > "$TMP/root/.env"
  cd "$TMP/proj"
  run env -u AWS_REGION DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" dev
  assert_success
  assert_output --partial "REGION:ap-south-1"
}

@test "launcher: resolves \${VAR} references from the repo .env" {
  _fake_uvx
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "env": { "AWS_ACCESS_KEY_ID": "${ENVFILE_KEY}" } } } }
EOF
  echo 'ENVFILE_KEY=FROMDOTENV' > "$TMP/root/.env"
  cd "$TMP/proj"
  run env -u ENVFILE_KEY DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "KEY:FROMDOTENV"
}

@test "launcher: the profile form passes --profile through to sts" {
  _fake_uvx
  _fake_aws_account "123456789012"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  run grep -c -- "--profile ro" "$TMP/aws-argv.log"
  assert_output "1"
}

# ── install.sh ────────────────────────────────────────────────────────────────

@test "install.sh: completes non-interactively without writing a region" {
  mkdir -p "$TMP/bin" "$TMP/root" "$TMP/home"
  echo '{"project_name":"demo"}' > "$TMP/root/.devbot.global.jsonc"

  for cmd in uv unzip; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/$cmd"
    chmod +x "$TMP/bin/$cmd"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/aws"
  chmod +x "$TMP/bin/aws"
  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do [[ "${args[$i]}" == "-o" ]] && out="${args[$((i+1))]}"; done
[[ -n "$out" ]] && echo "# rules" > "$out"
exit 0
EOF
  chmod +x "$TMP/bin/curl"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$INSTALL" </dev/null
  assert_success

  # No region menu and no aws_region write — the region lives on each connection.
  run python3 "$READ_JSONC" "$TMP/root/.devbot.global.jsonc" aws_region
  assert_output ""
}

@test "install.sh: never logs in" {
  run grep -qE 'aws (login|sso login)' "$INSTALL"
  assert_failure
}

# ── up.sh — verify-only ───────────────────────────────────────────────────────

@test "up.sh: verifies every declared connection" {
  _fake_aws_account "123456789012"
  _aws_global <<'EOF'
{ "aws_connections": {
    "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" },
    "dev":  { "region": "eu-west-1", "profile": "dev-ro" }
} }
EOF
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "connection 'prod' — credentials valid"
  assert_output --partial "connection 'dev' — credentials valid"
}

@test "up.sh: warns (does not fail) when a connection's credentials are unusable" {
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\nexit 255\n' > "$TMP/bin/aws"
  chmod +x "$TMP/bin/aws"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "credentials unusable"
}

@test "up.sh: never logs in" {
  run grep -qE 'aws (login|sso login)' "$UP"
  assert_failure
}
