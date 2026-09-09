#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp_translate_tests.bats
# Tests for mcp_translate.py — the single canonical→harness translator that
# both harness adapters (bin/init.sh opencode registration, claudecode
# _wire_mcp) and mcp_key_is_current.py consume.
#
# Canonical module manifest (src/agentic/<module>/mcp.json):
#   { "mcp": { "<server>": { "type": "stdio"|"http",
#                            "command": [argv...],   // stdio
#                            "url": "...",           // http
#                            "oauth": bool,          // http passthrough
#                            "env": { "K": "V" } } } }
#
# Tokens resolved at translation: {harness-dir} → .opencode/.claude,
# {host} → opencode/claude; placeholders __GPU_ENABLED__ and __DEV_BOT_ROOT__
# resolved only when --gpu/--root are given (mcp_key_is_current leaves them
# literal and applies its own placeholder-insensitive comparison).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/mcp_translate.py"

  WORK="$(mktemp -d)"

  # stdio server launched through a bash wrapper with a harness-dir token.
  cat > "$WORK/stdio.json" <<'JSON_EOF'
{
  "mcp": {
    "graphify": {
      "type": "stdio",
      "command": ["bash", "-c", "exec bash {harness-dir}/graphify-serve.sh graphify-out/graph.json"],
      "env": { "LOG_LEVEL": "info" }
    }
  }
}
JSON_EOF

  # http server (context7-style remote).
  cat > "$WORK/http.json" <<'JSON_EOF'
{
  "mcp": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "oauth": false
    }
  }
}
JSON_EOF

  # Direct-binary stdio server (no wrapper) — claudecode gets no args key.
  cat > "$WORK/direct.json" <<'JSON_EOF'
{
  "mcp": {
    "codebase-memory": { "type": "stdio", "command": ["codebase-memory-mcp"] }
  }
}
JSON_EOF

  # Host token (codebase-index --host) + a GPU placeholder in env.
  cat > "$WORK/tokens.json" <<'JSON_EOF'
{
  "mcp": {
    "codebase-index": {
      "type": "stdio",
      "command": ["bash", "-c", "exec node {harness-dir}/codebase-index-mcp-wrapper.js npx opencode-codebase-index-mcp --project . --host {host}"],
      "env": { "QMD_LLAMA_GPU": "__GPU_ENABLED__", "MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories" }
    }
  }
}
JSON_EOF

  # Underscore-prefixed keys are annotations and must be ignored.
  cat > "$WORK/annotated.json" <<'JSON_EOF'
{
  "mcp": {
    "_note": "this must not appear in output",
    "qmd": { "type": "stdio", "command": ["qmd", "mcp"] }
  }
}
JSON_EOF

  # Canonical JSON (single-line) for jq -S comparison.
  cat > "$WORK/invalid-type.json" <<'JSON_EOF'
{
  "mcp": {
    "bad": { "type": "remote", "url": "https://example.com/mcp" }
  }
}
JSON_EOF

  cat > "$WORK/missing-command.json" <<'JSON_EOF'
{
  "mcp": {
    "bad": { "type": "stdio" }
  }
}
JSON_EOF

  # Leftover harness-shaped fields must fail loudly, not silently drop.
  cat > "$WORK/http-with-command.json" <<'JSON_EOF'
{
  "mcp": {
    "bad": { "type": "http", "url": "https://example.com/mcp", "command": ["npx", "mcp-server"] }
  }
}
JSON_EOF

  cat > "$WORK/stdio-with-oauth.json" <<'JSON_EOF'
{
  "mcp": {
    "bad": { "type": "stdio", "command": ["qmd", "mcp"], "oauth": false }
  }
}
JSON_EOF
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

assert_json_eq() {
  # Compare two JSON blobs key-order-insensitively.
  assert_equal "$(jq -S . <<<"$1")" "$(jq -S . <<<"$2")"
}

@test "stdio entry translates to opencode local shape with environment" {
  run python3 "$TOOL" "$WORK/stdio.json" opencode
  assert_success
  assert_json_eq "$output" '{"graphify": {"type": "local", "command": ["bash", "-c", "exec bash .opencode/graphify-serve.sh graphify-out/graph.json"], "environment": {"LOG_LEVEL": "info"}}}'
}

@test "stdio entry translates to claudecode stdio shape with command+args and env" {
  run python3 "$TOOL" "$WORK/stdio.json" claudecode
  assert_success
  assert_json_eq "$output" '{"graphify": {"type": "stdio", "command": "bash", "args": ["-c", "exec bash .claude/graphify-serve.sh graphify-out/graph.json"], "env": {"LOG_LEVEL": "info"}}}'
}

@test "http entry translates to opencode remote (oauth kept)" {
  run python3 "$TOOL" "$WORK/http.json" opencode
  assert_success
  assert_json_eq "$output" '{"context7": {"type": "remote", "url": "https://mcp.context7.com/mcp", "oauth": false}}'
}

@test "http entry translates to claudecode http (oauth dropped)" {
  run python3 "$TOOL" "$WORK/http.json" claudecode
  assert_success
  assert_json_eq "$output" '{"context7": {"type": "http", "url": "https://mcp.context7.com/mcp"}}'
}

@test "direct-binary stdio entry gets no args key on claudecode" {
  run python3 "$TOOL" "$WORK/direct.json" claudecode
  assert_success
  assert_json_eq "$output" '{"codebase-memory": {"type": "stdio", "command": "codebase-memory-mcp"}}'
}

@test "{harness-dir} and {host} tokens resolve per harness" {
  # {host} is the PRODUCT name: opencode, and "claude" for claudecode (its
  # module/dir name is claudecode/.claude — assert an exact boundary so a
  # "claudecode" resolution cannot false-pass on the "claude" substring).
  run python3 "$TOOL" "$WORK/tokens.json" claudecode
  assert_success
  assert_output --partial "exec node .claude/codebase-index-mcp-wrapper.js"
  assert_output --regexp -- '--host claude[" ]'
  refute_output --partial 'claudecode'

  run python3 "$TOOL" "$WORK/tokens.json" opencode
  assert_success
  assert_output --partial "exec node .opencode/codebase-index-mcp-wrapper.js"
  assert_output --regexp -- '--host opencode[" ]'
}

@test "placeholders resolved when --gpu/--root given, left literal otherwise" {
  run python3 "$TOOL" "$WORK/tokens.json" opencode --gpu cuda --root /opt/dev-bot
  assert_success
  assert_output --partial '"QMD_LLAMA_GPU": "cuda"'
  assert_output --partial '"MDCTX_ROOT": "/opt/dev-bot/storage/global-memories"'

  run python3 "$TOOL" "$WORK/tokens.json" opencode
  assert_success
  assert_output --partial '"QMD_LLAMA_GPU": "__GPU_ENABLED__"'
  assert_output --partial '"MDCTX_ROOT": "__DEV_BOT_ROOT__/storage/global-memories"'
}

@test "underscore-prefixed server keys are ignored" {
  run python3 "$TOOL" "$WORK/annotated.json" opencode
  assert_success
  assert_json_eq "$output" '{"qmd": {"type": "local", "command": ["qmd", "mcp"]}}'
}

@test "unknown transport type fails loudly" {
  run python3 "$TOOL" "$WORK/invalid-type.json" opencode
  assert_failure
  assert_output --partial "unsupported transport type 'remote'"
}

@test "stdio entry without command fails loudly" {
  run python3 "$TOOL" "$WORK/missing-command.json" opencode
  assert_failure
  assert_output --partial "command"
}

@test "http entry with a command fails loudly" {
  run python3 "$TOOL" "$WORK/http-with-command.json" opencode
  assert_failure
  assert_output --partial "command"
}

@test "stdio entry with oauth fails loudly" {
  run python3 "$TOOL" "$WORK/stdio-with-oauth.json" opencode
  assert_failure
  assert_output --partial "oauth"
}

@test "unsupported harness fails loudly" {
  run python3 "$TOOL" "$WORK/stdio.json" netbeans
  assert_failure
}
