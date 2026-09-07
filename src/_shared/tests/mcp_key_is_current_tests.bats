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
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/mcp_key_is_current.py"

  WORK="$(mktemp -d)"
  # A config with module-managed servers registered (matches module template).
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  // opencode runtime config
  "mcp": {
    "devbot-tools": { "type": "local", "command": ["x"] },
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": "cuda", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF

  cat > "$WORK/qmd-module.json" <<'JSON_EOF'
{
  "mcpServers": {
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": "__GPU_ENABLED__", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSON_EOF

  cat > "$WORK/devbot-tools-module.json" <<'JSON_EOF'
{
  "mcpServers": {
    "devbot-tools": { "type": "local", "command": ["x"] }
  }
}
JSON_EOF
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

@test "exit 0 when registered def matches module template (no removal needed)" {
  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/qmd-module.json" "qmd"
  assert_success
}

@test "exit 0 when __GPU_ENABLED__ resolves to the config's GPU value" {
  # The config resolved __GPU_ENABLED__ → "cuda"; that must count as current.
  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/qmd-module.json" "qmd"
  assert_success
}

@test "exit 1 when command differs from module template (stale)" {
  cat > "$WORK/stale-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "OLD-COMMAND"], "environment": { "QMD_LLAMA_GPU": true } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/stale-config.jsonc" "$WORK/qmd-module.json" "qmd"
  assert_failure
}

@test "exit 1 when env shape differs (audit-28 stale qmd env)" {
  # Old form: QMD_LLAMA_GPU as a boolean, no QMD_EXPAND_CONTEXT_SIZE.
  cat > "$WORK/old-env-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd", "mcp"], "environment": { "QMD_LLAMA_GPU": true } }
  }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/old-env-config.jsonc" "$WORK/qmd-module.json" "qmd"
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

  run python3 "$TOOL" "$WORK/no-qmd.jsonc" "$WORK/qmd-module.json" "qmd"
  assert_success
}

@test "exit 0 when key no longer declared by module template" {
  cat > "$WORK/no-qmd-module.json" <<'JSON_EOF'
{
  "mcpServers": {
    "other": { "type": "stdio", "command": "other" }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "$WORK/no-qmd-module.json" "qmd"
  assert_success
}

@test "handles .mcp.json mcpServers shape (claudecode)" {
  cat > "$WORK/.mcp.json" <<'JSONC_EOF'
{
  "mcpServers": {
    "qmd": { "type": "stdio", "command": "qmd", "args": ["mcp"], "environment": { "QMD_LLAMA_GPU": "false", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSONC_EOF
  cat > "$WORK/qmd-claudecode-module.json" <<'JSON_EOF'
{
  "mcpServers": {
    "qmd": { "type": "stdio", "command": "qmd", "args": ["mcp"], "environment": { "QMD_LLAMA_GPU": "__GPU_ENABLED__", "QMD_EXPAND_CONTEXT_SIZE": "512" } }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/.mcp.json" "$WORK/qmd-claudecode-module.json" "qmd"
  assert_success
}

@test "exit 0 when __DEV_BOT_ROOT__ resolves to the config's install path (suffix matches)" {
  # The config resolved __DEV_BOT_ROOT__ → "/opt/dev-bot" at registration; the
  # suffix after the placeholder must match for the entry to stay current.
  cat > "$WORK/mdctx-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": {
      "type": "local",
      "command": ["mdctx-mcp"],
      "environment": {
        "MDCTX_ROOT": "/opt/dev-bot/storage/global-memories",
        "MDCTX_INDEX": "/opt/dev-bot/storage/.mdctx/context-index.json"
      }
    }
  }
}
JSONC_EOF
  cat > "$WORK/mdctx-module.json" <<'JSON_EOF'
{
  "mdctx": {
    "type": "local",
    "command": ["mdctx-mcp"],
    "environment": {
      "MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories",
      "MDCTX_INDEX": "__DEV_BOT_ROOT__/storage/.mdctx/context-index.json"
    }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/mdctx-config.jsonc" "$WORK/mdctx-module.json" "mdctx"
  assert_success
}

@test "exit 1 when __DEV_BOT_ROOT__-resolved path has a different suffix (stale)" {
  # Root layout drifted from the module template (e.g. store moved): the
  # placeholder must not mask the structural difference.
  cat > "$WORK/mdctx-stale-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": {
      "type": "local",
      "command": ["mdctx-mcp"],
      "environment": {
        "MDCTX_ROOT": "/opt/dev-bot/elsewhere/global-memories",
        "MDCTX_INDEX": "/opt/dev-bot/storage/.mdctx/context-index.json"
      }
    }
  }
}
JSONC_EOF
  cat > "$WORK/mdctx-module.json" <<'JSON_EOF'
{
  "mdctx": {
    "type": "local",
    "command": ["mdctx-mcp"],
    "environment": {
      "MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories",
      "MDCTX_INDEX": "__DEV_BOT_ROOT__/storage/.mdctx/context-index.json"
    }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/mdctx-stale-config.jsonc" "$WORK/mdctx-module.json" "mdctx"
  assert_failure
}

@test "exit 1 when __DEV_BOT_ROOT__ env key is missing from config (stale)" {
  # Config predates the mdctx env (or was hand-edited to drop it): the missing
  # env key must read as stale so reset removes and init re-registers.
  cat > "$WORK/mdctx-noenv-config.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "mdctx": { "type": "local", "command": ["mdctx-mcp"] }
  }
}
JSONC_EOF
  cat > "$WORK/mdctx-module.json" <<'JSON_EOF'
{
  "mdctx": {
    "type": "local",
    "command": ["mdctx-mcp"],
    "environment": {
      "MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories",
      "MDCTX_INDEX": "__DEV_BOT_ROOT__/storage/.mdctx/context-index.json"
    }
  }
}
JSON_EOF

  run python3 "$TOOL" "$WORK/mdctx-noenv-config.jsonc" "$WORK/mdctx-module.json" "mdctx"
  assert_failure
}
