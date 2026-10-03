#!/usr/bin/env bats
# =============================================================================
# src/agentic/aws/tests/aws_tests.bats
# Tests for the AWS module:
#   - init.sh (per-connection dynamic manifests, prune/reconcile, launcher link)
#   - aws-mcp-proxy.sh (connection resolution: env XOR profile, region, account pin)
#   - install.sh / up.sh (non-interactive dependency setup + verify-only)
# Network/auth steps are exercised only via fake binaries on PATH.
# =============================================================================

bats_require_minimum_version 1.5.0

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
  UPDATE="$MODULE_DIR/update.sh"
  INIT="$MODULE_DIR/init.sh"

  TMP="$(mktemp -d)"
  mkdir -p "$TMP/home"
}

teardown() {
  rm -rf "$TMP"
}

# A fake mcp-proxy-for-aws-cli (the installed uv tool) that reports the argv AND
# the credential environment it inherited.
_fake_proxy() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/mcp-proxy-for-aws-cli" <<'EOF'
#!/usr/bin/env bash
echo "ARGS:$*"
echo "KEY:${AWS_ACCESS_KEY_ID:-<unset>}"
echo "SECRET:${AWS_SECRET_ACCESS_KEY:-<unset>}"
echo "REGION:${AWS_REGION:-<unset>}"
echo "PROFILE:${AWS_PROFILE:-<unset>}"
echo "PROFILES:${AWS_MCP_PROXY_PROFILES:-<unset>}"
EOF
  chmod +x "$TMP/bin/mcp-proxy-for-aws-cli"
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

# Fake binaries for install.sh/update.sh: uv (records argv), unzip, aws, curl.
# The uv fake answers `tool list` from $TMP/uv-tool-list.txt, so a test chooses
# whether the MCP proxy already looks installed.
_fake_install_bins() {
  mkdir -p "$TMP/bin" "$TMP/root"
  echo '{"project_name":"demo"}' > "$TMP/root/.devbot.global.jsonc"

  cat > "$TMP/bin/uv" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/uv-argv.log"
if [[ "\${1:-} \${2:-}" == "tool list" ]]; then
  cat "$TMP/uv-tool-list.txt" 2>/dev/null || true
fi
exit 0
EOF
  chmod +x "$TMP/bin/uv"

  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/unzip"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/aws"
  chmod +x "$TMP/bin/unzip" "$TMP/bin/aws"

  cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do [[ "${args[$i]}" == "-o" ]] && out="${args[$((i+1))]}"; done
[[ -n "$out" ]] && echo "# rules" > "$out"
exit 0
EOF
  chmod +x "$TMP/bin/curl"
}

# ── init.sh — per-connection dynamic manifests ────────────────────────────────

_aws_seed_project() {
  mkdir -p "$TMP/proj" "$TMP/root/storage/aws/rules"
  # A git dir, so the local-exclude path is exercised.
  mkdir -p "$TMP/proj/.git/info"
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

@test "init.sh: excludes the copied rules from the project's history" {
  # The file lands in a dir the memory module un-ignores, so it needs its own
  # local exclude entry or it shows up as untracked noise in every project.
  _aws_seed_project
  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success

  run cat "$TMP/proj/.git/info/exclude"
  assert_output --partial "# >>> DEVBOT - aws"
  assert_output --partial ".agents/memory/active/aws-agent-rules.md"

  # Idempotent: a second run must not duplicate the section.
  env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj" >/dev/null
  run grep -c "# >>> DEVBOT - aws" "$TMP/proj/.git/info/exclude"
  assert_output "1"
}

@test "init.sh: writes no rules when the module is disabled for the project" {
  _aws_seed_project
  echo '{"modules": {"aws": false}}' > "$TMP/proj/.devbot.project.jsonc"

  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success
  assert_output --partial "module disabled for this project"

  assert [ ! -e "$TMP/proj/.agents/memory/active/aws-agent-rules.md" ]
  assert [ ! -e "$TMP/proj/.git/info/exclude" ]
}

@test "init.sh: a project without git is not an error" {
  _aws_seed_project
  rm -r "$TMP/proj/.git"

  run env DEV_BOT_ROOT="$TMP/root" bash "$INIT" "$TMP/proj"
  assert_success
  assert_output --partial "not a git repo"
  assert [ -f "$TMP/proj/.agents/memory/active/aws-agent-rules.md" ]
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
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER"
  assert_failure
  assert_output --partial "usage"
}

@test "launcher: rejects an undeclared connection" {
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" ghost
  assert_failure
  assert_output --partial "not declared"
}

@test "launcher: env form exports resolved keys, never on argv" {
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "both": { "region": "eu-west-1", "profile": "ro", "env": { "AWS_ACCESS_KEY_ID": "x" } } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" both
  assert_failure
  assert_output --partial "both env and profile"
}

@test "launcher: rejects a connection with neither env nor profile" {
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "empty": { "region": "eu-west-1" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" empty
  assert_failure
  assert_output --partial "neither env nor profile"
}

@test "launcher: account_id match proceeds" {
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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
  _fake_proxy
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

@test "launcher: execs the installed proxy with the endpoint and metadata" {
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "ARGS:https://aws-mcp.us-east-1.api.aws/mcp"
  assert_output --partial "--metadata INSTALL_SOURCE=agent-toolkit-core"
  assert_output --partial "--metadata AWS_REGION=eu-central-1"
}

@test "launcher: refuses to start when the proxy is not installed" {
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  # No proxy binary on PATH, and an empty HOME so the ~/.local/bin fallback misses.
  run --separate-stderr env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" \
    PATH="/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_failure
  # MCP speaks JSON-RPC on stdout: the diagnostic must be on stderr only.
  assert_equal "$output" ""
  [[ "$stderr" == *"not installed"* ]]
}

@test "launcher: survives a missing HOME with the actionable error" {
  # Without the ${HOME:-} guard, set -u aborts on "HOME: unbound variable" and
  # the operator never sees the fix instruction.
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run --separate-stderr env -u HOME DEV_BOT_ROOT="$TMP/root" \
    PATH="/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_failure
  assert_equal "$output" ""
  [[ "$stderr" == *"not installed"* ]]
}

@test "launcher: --check verifies credentials without the proxy installed" {
  _fake_aws_account "123456789012"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
    bash "$LAUNCHER" --check prod
  assert_success
  assert_output --partial "OK (account 123456789012)"
}

@test "launcher: --which prints the resolved proxy path" {
  _fake_proxy
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$LAUNCHER" --which
  assert_success
  assert_output "$TMP/bin/mcp-proxy-for-aws-cli"
}

@test "launcher: --which fails when the proxy is not installed" {
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run --separate-stderr env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" \
    PATH="/usr/bin:/bin" bash "$LAUNCHER" --which
  assert_failure
  assert_equal "$output" ""
  [[ "$stderr" == *"not installed"* ]]
}

@test "launcher: falls back to the ~/.local/bin proxy when it is not on PATH" {
  _fake_proxy
  mkdir -p "$TMP/home/.local/bin"
  cp "$TMP/bin/mcp-proxy-for-aws-cli" "$TMP/home/.local/bin/"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro" } } }
EOF
  cd "$TMP/proj"
  run env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" PATH="/usr/bin:/bin" bash "$LAUNCHER" prod
  assert_success
  assert_output --partial "ARGS:https://aws-mcp.us-east-1.api.aws/mcp"
}

@test "launcher: never resolves the proxy through uvx at launch" {
  # Code lines only — the header comment explains why, and names uvx.
  run bash -c "grep -v '^[[:space:]]*#' '$LAUNCHER' | grep -q 'uvx'"
  assert_failure
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

@test "install.sh: installs the pinned MCP proxy as a uv tool" {
  _fake_install_bins
  : > "$TMP/uv-tool-list.txt"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$INSTALL" </dev/null
  assert_success

  run grep -c -- "tool install mcp-proxy-for-aws-cli==1.7.0" "$TMP/uv-argv.log"
  assert_output "1"
}

@test "install.sh: skips the MCP proxy when the pinned version is already installed" {
  _fake_install_bins
  printf 'mcp-proxy-for-aws-cli v1.7.0\n- mcp-proxy-for-aws-cli\n' > "$TMP/uv-tool-list.txt"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$INSTALL" </dev/null
  assert_success

  run grep -c -- "tool install mcp-proxy-for-aws-cli" "$TMP/uv-argv.log"
  assert_output "0"
}

@test "install.sh: matches the pinned proxy even when uv tool list is large" {
  _fake_install_bins
  # The matching line first, then output far larger than a pipe buffer: reading
  # uv directly with `grep -q` would SIGPIPE uv (pipefail) and read as absent,
  # triggering a pointless reinstall.
  {
    echo 'mcp-proxy-for-aws-cli v1.7.0'
    seq 1 20000 | sed 's/^/other-tool v0.0.0 /'
  } > "$TMP/uv-tool-list.txt"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$INSTALL" </dev/null
  assert_success

  run grep -c -- "tool install mcp-proxy-for-aws-cli" "$TMP/uv-argv.log"
  assert_output "0"
}

@test "update.sh: installs the pinned MCP proxy as a uv tool" {
  _fake_install_bins
  : > "$TMP/uv-tool-list.txt"

  run env HOME="$TMP/home" DEV_BOT_ROOT="$TMP/root" PATH="$TMP/bin:/usr/bin:/bin" bash "$UPDATE" </dev/null
  assert_success

  run grep -c -- "tool install mcp-proxy-for-aws-cli==1.7.0" "$TMP/uv-argv.log"
  assert_output "1"
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

@test "up.sh: warns when the AWS MCP proxy is not installed" {
  _fake_aws_account "123456789012"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  run env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "credentials valid"
  assert_output --partial "proxy not installed"
}

@test "up.sh: finds the proxy through the launcher's ~/.local/bin fallback" {
  _fake_aws_account "123456789012"
  mkdir -p "$TMP/home/.local/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/home/.local/bin/mcp-proxy-for-aws-cli"
  chmod +x "$TMP/home/.local/bin/mcp-proxy-for-aws-cli"
  _aws_global <<'EOF'
{ "aws_connections": { "prod": { "region": "eu-central-1", "profile": "ro", "account_id": "123456789012" } } }
EOF
  # Not on PATH — the launcher's fallback is the only way it can be found.
  run env DEV_BOT_ROOT="$TMP/root" HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" bash "$UP"
  assert_success
  assert_output --partial "proxy present"
}

# ── pre.sh — prerequisite classification ──────────────────────────────────────
#
# A prereq this module's install.sh/update.sh provisions is a NOTICE before the
# first install (not a failure); a manual prereq (curl/wget) is a fatal ERROR.

# Symlink the shell utilities pre.sh (and the functions.sh it sources) need, so
# a PATH built only from this dir cannot fall through to the host's real
# unzip/uv/aws — the classification paths must be reachable deterministically.
_pre_bin_dir() {
  mkdir -p "$TMP/pre-bin"
  local real
  for real in bash dirname head; do
    ln -sf "$(command -v "$real")" "$TMP/pre-bin/$real"
  done
}

@test "pre.sh: notices module-provisioned prereqs and continues" {
  _pre_bin_dir
  mkdir -p "$TMP/home"
  # curl + jq present; unzip/uv/proxy/aws absent (install/update provides them).
  local c
  for c in curl jq; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/pre-bin/$c"
    chmod +x "$TMP/pre-bin/$c"
  done

  run env HOME="$TMP/home" PATH="$TMP/pre-bin" bash "$MODULE_DIR/pre.sh"
  assert_success
  assert_output --partial "NOTICE"
  assert_output --partial "will install it"
  refute_output --partial "ERROR"
}

@test "pre.sh: errors when a manual prereq (curl/wget) is missing" {
  _pre_bin_dir
  mkdir -p "$TMP/home"

  run env HOME="$TMP/home" PATH="$TMP/pre-bin" bash "$MODULE_DIR/pre.sh"
  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial "curl nor wget"
}

@test "pre.sh: all prereqs present reports ok, no notice" {
  _pre_bin_dir
  mkdir -p "$TMP/home"
  local c
  for c in curl jq unzip uv mcp-proxy-for-aws-cli; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/pre-bin/$c"
    chmod +x "$TMP/pre-bin/$c"
  done
  # pre.sh pipes `aws --version` to head, so the fake must print a line.
  printf '#!/usr/bin/env bash\necho "aws-cli/2.0.0"\n' > "$TMP/pre-bin/aws"
  chmod +x "$TMP/pre-bin/aws"

  run env HOME="$TMP/home" PATH="$TMP/pre-bin" bash "$MODULE_DIR/pre.sh"
  assert_success
  refute_output --partial "NOTICE"
  refute_output --partial "ERROR"
}
