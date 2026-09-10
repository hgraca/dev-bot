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

# audit-59 FAIL-1: a project guard with the same regex as a global guard must
# win (project config overrides global defaults), so its message is reported.
@test "project guard overrides a global guard with the same regex" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$tmpdir/.devbot.global.jsonc" << 'EOF'
{ "guards": [ { "regex": "sudo .*", "message": "sudo is blocked (global)" } ] }
EOF
  cat > "$tmpdir/.devbot.project.jsonc" << 'EOF'
{ "guards": [ { "regex": "sudo .*", "message": "sudo requires approval (project)" } ] }
EOF

  run bun "$MODULE_DIR/tools/guards.ts" --command "sudo echo test" \
    --global-config "$tmpdir/.devbot.global.jsonc" \
    --project-config "$tmpdir/.devbot.project.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
  assert_output --partial 'sudo requires approval (project)'
  refute_output --partial 'sudo is blocked (global)'
  rm -rf "$tmpdir"
}

# The reorder must not stop a global guard from matching when the project's
# rules do not — guards are deny-only, so the blocked set is the union of all
# matching rules and precedence only chooses the message.
@test "non-matching project guard falls through to the global guard" {
  local tmpdir
  tmpdir="$(mktemp -d "$FIXTURES/tmp.XXXXXX")"
  cat > "$tmpdir/.devbot.global.jsonc" << 'EOF'
{ "guards": [ { "regex": "rm -rf", "message": "rm -rf is blocked (global)" } ] }
EOF
  cat > "$tmpdir/.devbot.project.jsonc" << 'EOF'
{ "guards": [ { "regex": "docker system prune", "message": "prune blocked (project)" } ] }
EOF

  run bun "$MODULE_DIR/tools/guards.ts" --command "rm -rf /tmp/fallthrough" \
    --global-config "$tmpdir/.devbot.global.jsonc" \
    --project-config "$tmpdir/.devbot.project.jsonc"
  assert_success
  assert_output --partial '"blocked":true'
  assert_output --partial 'rm -rf is blocked (global)'
  rm -rf "$tmpdir"
}
