#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp_key_is_current_tests.bats
# Tests for mcp_key_is_current.py — the skip-if-unchanged guard used by
# reset.sh (audit-32 NOTE: reinit byte-idempotency).
#
# reset.sh runs before init on every reinit and drops module-managed MCP keys
# so init re-registers them fresh. Dropping a key that ALREADY matches its
# module template is pure churn: init re-appends it at the end of the mcp map,
# reordering keys so the second reinit produces a different opencode.jsonc than
# the first. This helper reports whether removal is needed (key stale) so reset
# only touches genuinely outdated entries.
#
# The module template is the canonical mcp.json, translated to the harness
# shape being compared (mcp_translate.py). Placeholders are compared
# placeholder-insensitively: __GPU_ENABLED__ accepts any resolved string,
# __DEV_BOT_ROOT__ requires the suffix to match, and {env:VAR} values are
# current whether the config holds the literal, a resolved value, or omits the
# key entirely.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/mcp_key_is_current.py"

  WORK="$(mktemp -d)"

  # Canonical module manifest (single source, harness-agnostic).
  cat > "$WORK/qmd-module.json" <<'JSON_EOF'
{
  "mcp": {
    "qmd": {
      "type": "stdio",
      "command": ["qmd", "mcp"],
      "env": {
        "QMD_LLAMA_GPU": "__GPU_ENABLED__",
        "QMD_EXPAND_CONTEXT_SIZE": "512"
      }
    }
  }
}
JSON_EOF

  cat > "$WORK/devbot-tools-module.json" <<'JSON_EOF'
{
  "mcp": {
    "devbot-tools": { "type": "stdio", "command": ["x"] }
  }
}
JSON_EOF

  # opencode runtime config with module-managed servers registered.
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  // opencode runtime config
  "mcp": {
    "devbot-tools": { "type": "local", "command": ["x"] },
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": "cuda", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

@test "exit 0 when opencode def matches translated canonical (no removal)" {
  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_success
}

@test "exit 0 when __GPU_ENABLED__ resolves to any config GPU value" {
  # cuda (Linux), metal (macOS) or false (no GPU) are all current.
  sed -i 's/"QMD_LLAMA_GPU": "cuda"/"QMD_LLAMA_GPU": "metal"/' "$WORK/opencode.jsonc"
  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_success
}

@test "exit 0 when .mcp.json def matches canonical translated to claudecode" {
  cat > "$WORK/.mcp.json" <<'JSONC_EOF'
{
  "mcpServers": {
    "qmd": { "type": "stdio", "command": "qmd", "args": ["mcp"], "env": { "QMD_LLAMA_GPU": "false", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/.mcp.json" "$WORK/qmd-module.json" "qmd" claudecode
  assert_success
}

@test "exit 1 when command differs from module template (stale)" {
  cat > "$WORK/stale-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "OLD-COMMAND"], "environment": { "QMD_LLAMA_GPU": "cuda", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/stale-config.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_failure
}

@test "exit 1 when env shape differs (audit-28 stale qmd env: boolean GPU)" {
  cat > "$WORK/old-env-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": true, "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/old-env-config.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_failure
}

@test "exit 1 when config entry still carries legacy enabled field" {
  # Pre-consolidation configs have "enabled": true; the translated canonical
  # template has none — stale, so reset drops and init re-registers clean.
  cat > "$WORK/enabled-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "enabled": true, "environment": { "QMD_LLAMA_GPU": "cuda", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/enabled-config.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_failure
}

@test "exit 0 when key absent from config (nothing to remove)" {
  cat > "$WORK/no-qmd.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "devbot-tools": { "type": "local", "command": ["x"] }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/no-qmd.jsonc" "$WORK/qmd-module.json" "qmd" opencode
  assert_success
}

@test "exit 0 when key no longer declared by module template" {
  cat > "$WORK/no-qmd-module.json" <<'JSON_EOF'
{
  "mcp": {
    "other": { "type": "stdio", "command": ["other"] }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/no-qmd-module.json" "qmd" opencode
  assert_success
}

@test "exit 0 when __DEV_BOT_ROOT__ suffix matches; exit 1 on drift or missing key" {
  cat > "$WORK/mdctx-module.json" <<'JSON_EOF'
{
  "mcp": {
    "mdctx": {
      "type": "stdio",
      "command": ["mdctx-mcp"],
      "env": {
        "MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories",
        "MDCTX_INDEX": "__DEV_BOT_ROOT__/storage/.mdctx/context-index.json"
      }
    }
  }
}
JSON_EOF

  # Match: root resolved to /opt/dev-bot, suffixes intact.
  cat > "$WORK/mdctx-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": { "type": "local", "command": ["mdctx-mcp"], "environment": {
      "MDCTX_ROOT": "/opt/dev-bot/storage/global-memories",
      "MDCTX_INDEX": "/opt/dev-bot/storage/.mdctx/context-index.json" } }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/mdctx-config.jsonc" "$WORK/mdctx-module.json" "mdctx" opencode
  assert_success

  # Drift: one resolved path moved outside the template layout.
  cat > "$WORK/mdctx-stale-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": { "type": "local", "command": ["mdctx-mcp"], "environment": {
      "MDCTX_ROOT": "/opt/dev-bot/elsewhere/global-memories",
      "MDCTX_INDEX": "/opt/dev-bot/storage/.mdctx/context-index.json" } }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/mdctx-stale-config.jsonc" "$WORK/mdctx-module.json" "mdctx" opencode
  assert_failure

  # Missing env key entirely (config predates the env block).
  cat > "$WORK/mdctx-noenv-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": { "type": "local", "command": ["mdctx-mcp"] }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/mdctx-noenv-config.jsonc" "$WORK/mdctx-module.json" "mdctx" opencode
  assert_failure
}

@test "{env:VAR} values are current: {env:} literal (opencode), \${} native (claudecode), or absent" {
  cat > "$WORK/signoz-module.json" <<'JSON_EOF'
{
  "mcp": {
    "signoz": {
      "type": "stdio",
      "command": ["signoz-mcp-server"],
      "env": { "SIGNOZ_URL": "https://signoz.get-e.com", "SIGNOZ_API_KEY": "{env:SIGNOZ_AUTH_TOKEN}" }
    }
  }
}
JSON_EOF

  # opencode holds the literal {env:...} — opencode interpolates at launch.
  cat > "$WORK/signoz-opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "signoz": { "type": "local", "command": ["signoz-mcp-server"], "environment": {
      "SIGNOZ_URL": "https://signoz.get-e.com", "SIGNOZ_API_KEY": "{env:SIGNOZ_AUTH_TOKEN}" } }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/signoz-opencode.jsonc" "$WORK/signoz-module.json" "signoz" opencode
  assert_success

  # claudecode holds the native ${VAR} token — Claude Code expands it at
  # launch; never a registration-resolved plaintext value.
  cat > "$WORK/signoz-claude-native.json" <<'JSONC_EOF'
{
  "mcpServers": {
    "signoz": { "type": "stdio", "command": "signoz-mcp-server", "env": {
      "SIGNOZ_URL": "https://signoz.get-e.com", "SIGNOZ_API_KEY": "${SIGNOZ_AUTH_TOKEN}" } }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/signoz-claude-native.json" "$WORK/signoz-module.json" "signoz" claudecode
  assert_success

  # Config omits the key entirely — still current.
  cat > "$WORK/signoz-claude-noenv.json" <<'JSONC_EOF'
{
  "mcpServers": {
    "signoz": { "type": "stdio", "command": "signoz-mcp-server", "env": { "SIGNOZ_URL": "https://signoz.get-e.com" } }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/signoz-claude-noenv.json" "$WORK/signoz-module.json" "signoz" claudecode
  assert_success
}
