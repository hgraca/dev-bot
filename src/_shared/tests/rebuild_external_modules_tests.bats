#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/rebuild_external_modules_tests.bats
# Tests for _devbot_rebuild_external_module_config in src/_shared/functions.sh.
#
# The declaration store and the vendor/ clones are global, shared by every
# registered project, so the rebuild must merge EVERY module's declarations —
# a module disabled in one project must not stop its external modules being
# provisioned for the others.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  SANDBOX="$(mktemp -d)"
  export DEV_BOT_ROOT="$SANDBOX"
  mkdir -p "$SANDBOX/src/_shared" "$SANDBOX/src/agentic" "$SANDBOX/src/tools"
  cp "$PROJECT_ROOT/src/_shared/merge_modules_jsonc.py" "$SANDBOX/src/_shared/"
  source "$PROJECT_ROOT/src/_shared/functions.sh"
}

teardown() {
  rm -rf "$SANDBOX"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# _declare_module <area> <module-name> <external-name>
_declare_module() {
  local area="$1" name="$2" ext="$3"
  mkdir -p "$SANDBOX/src/$area/$name"
  cat >"$SANDBOX/src/$area/$name/external-modules.json" <<EOF
{ "$ext": { "url": "https://example.com/$ext.git", "paths": { "skills": "skills" } } }
EOF
}

# Print the external_modules keys, one per line (config has no comments here).
_external_keys() {
  python3 -c "
import json
with open('$SANDBOX/.devbot.global.jsonc') as f:
    data = json.load(f)
print('\n'.join(sorted(data.get('external_modules', {}))))
"
}

# ── Tests ────────────────────────────────────────────────────────────────────

@test "rebuild: merges a declaration from a DISABLED module" {
  printf '%s\n' '{ "modules": { "off-umbrella": false } }' >"$SANDBOX/.devbot.global.jsonc"
  _declare_module agentic off-umbrella ext-off

  run _devbot_rebuild_external_module_config
  assert_success

  run _external_keys
  assert_output --partial "ext-off"
}

@test "rebuild: merges a declaration from a tool module" {
  printf '%s\n' '{ "modules": {} }' >"$SANDBOX/.devbot.global.jsonc"
  _declare_module tools some-tool ext-tool

  run _devbot_rebuild_external_module_config
  assert_success

  run _external_keys
  assert_output --partial "ext-tool"
}

@test "rebuild: creates the external_modules section when absent" {
  printf '%s\n' '{ "modules": {} }' >"$SANDBOX/.devbot.global.jsonc"
  _declare_module agentic on-umbrella ext-new

  run _devbot_rebuild_external_module_config
  assert_success

  run _external_keys
  assert_output --partial "ext-new"
}

@test "rebuild: is idempotent" {
  printf '%s\n' '{ "modules": {} }' >"$SANDBOX/.devbot.global.jsonc"
  _declare_module agentic on-umbrella ext-once

  _devbot_rebuild_external_module_config
  run _devbot_rebuild_external_module_config
  assert_success
  refute_output --partial "INSERTED"

  run _external_keys
  assert_output "ext-once"
}

@test "rebuild: a missing config is tolerated and nothing is declared" {
  rm -f "$SANDBOX/.devbot.global.jsonc"

  run _devbot_rebuild_external_module_config
  assert_success
  assert_output --partial "no external-modules.json declarations found"
}

@test "rebuild: a missing config with declarations does not crash" {
  rm -f "$SANDBOX/.devbot.global.jsonc"
  _declare_module agentic on-umbrella ext-x

  run _devbot_rebuild_external_module_config
  assert_success
}

@test "rebuild: an empty declarations file is a no-op" {
  printf '%s\n' '{ "modules": {} }' >"$SANDBOX/.devbot.global.jsonc"
  mkdir -p "$SANDBOX/src/agentic/empty-mod"
  printf '%s\n' '{}' >"$SANDBOX/src/agentic/empty-mod/external-modules.json"

  run _devbot_rebuild_external_module_config
  assert_success

  run python3 -c "import json; print(json.load(open('$SANDBOX/.devbot.global.jsonc')).get('external_modules', 'ABSENT'))"
  assert_output "ABSENT"
}
