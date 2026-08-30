#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "guards tool blocks rm -rf" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$tmpdir/.devbot.project.jsonc" << 'EOF'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked" } ] }
EOF

  run bun "$MODULE_DIR/tools/guards.ts" --command "rm -rf /tmp/foo" --project-config "$tmpdir/.devbot.project.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
  assert_output --partial 'rm -rf is blocked'
  rm -rf "$tmpdir"
}

@test "guards tool allows safe commands" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$tmpdir/.devbot.project.jsonc" << 'EOF'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked" } ] }
EOF

  run bun "$MODULE_DIR/tools/guards.ts" --command "ls -la" --project-config "$tmpdir/.devbot.project.jsonc"
  assert_success
  assert_output --partial '"blocked":false'
  rm -rf "$tmpdir"
}
