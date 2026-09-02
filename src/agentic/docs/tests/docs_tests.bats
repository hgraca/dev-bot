#!/usr/bin/env bats
# =============================================================================
# src/agentic/docs/tests/docs_tests.bats
# Tests for the docs module: use-case-map tool wrapping, skills, AppMap assets.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL_SH="$MODULE_DIR/tools/UseCaseMap/use-case-map.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"
  MOCK_PY="$FIXTURES/mock-create-use-case-map.py"
  SKILLS_DIR="$MODULE_DIR/skills"
  APP_MAP_ASSETS="$SKILLS_DIR/app-map/assets"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

# =============================================================================
# Shell wrapper tests
# =============================================================================

@test "bash wrapper: exists and is executable" {
  [[ -f "$TOOL_SH" ]]
  [[ -x "$TOOL_SH" ]]
}

@test "bash wrapper: invokes python3 with the .py file" {
  run cat "$TOOL_SH"
  assert_output --partial "create-use-case-map.py"
  assert_output --partial "exec python3"
}

@test "bash wrapper: python script exists at the expected path" {
  [[ -f "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" ]]
}

# =============================================================================
# TS CLI: error when Python script is missing
# =============================================================================

@test "missing python script: prints error and exits 1" {
  # Move the real script out of the way temporarily
  local REAL_PY="$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py"
  local TMP_MOVE="$FIXTURES/create-use-case-map.py.bak"

  mv "$REAL_PY" "$TMP_MOVE"

  run bash "$TOOL_SH" --project-root "$FIXTURES"

  # Restore before assertions (in case of failure)
  mv "$TMP_MOVE" "$REAL_PY"

  assert_failure
  assert_output --partial "script not found"
}

# =============================================================================
# TS CLI: flag parsing via bash wrapper (uses mock Python)
# =============================================================================

setup_mock() {
  # Replace real Python script with mock for pipe-through testing
  local REAL_PY="$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py"
  local REAL_BAK="$FIXTURES/create-use-case-map.py.real"

  if [[ ! -f "$REAL_BAK" ]]; then
    cp "$REAL_PY" "$REAL_BAK"
  fi
  cp "$MOCK_PY" "$REAL_PY"
}

teardown_mock() {
  local REAL_PY="$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py"
  local REAL_BAK="$FIXTURES/create-use-case-map.py.real"

  if [[ -f "$REAL_BAK" ]]; then
    mv "$REAL_BAK" "$REAL_PY"
  fi
}

@test "default: outputs JSON with default title when no flags" {
  setup_mock

  run bash "$TOOL_SH"
  teardown_mock

  assert_success
  assert_output --partial '"title": "Mock Map"'
  assert_output --partial '"subtitle": "Mock subtitle"'
}

@test "--title flag: custom title appears in output" {
  setup_mock

  run bash "$TOOL_SH" --title "My Custom Title"
  teardown_mock

  assert_success
  assert_output --partial '"title": "My Custom Title"'
}

@test "--subtitle flag: custom subtitle appears in output" {
  setup_mock

  run bash "$TOOL_SH" --subtitle "Custom Subtitle"
  teardown_mock

  assert_success
  assert_output --partial '"subtitle": "Custom Subtitle"'
}

@test "-t short flag: works as alias for --title" {
  setup_mock

  run bash "$TOOL_SH" -t "Short Flag Title"
  teardown_mock

  assert_success
  assert_output --partial '"title": "Short Flag Title"'
}

@test "-s short flag: works as alias for --subtitle" {
  setup_mock

  run bash "$TOOL_SH" -s "Short Sub"
  teardown_mock

  assert_success
  assert_output --partial '"subtitle": "Short Sub"'
}

@test "--component flag: sets component filter" {
  setup_mock

  run bash "$TOOL_SH" --component "Billing" --title "Billing Map"
  teardown_mock

  assert_success
  assert_output --partial '"title": "Billing Map"'
}

@test "-c short flag: works as alias for --component" {
  setup_mock

  run bash "$TOOL_SH" -c "Invoicing" -t "Invoicing Map"
  teardown_mock

  assert_success
  assert_output --partial '"title": "Invoicing Map"'
}

@test "--project-root flag: passes to script (no crash)" {
  setup_mock

  run bash "$TOOL_SH" --project-root "$FIXTURES"
  teardown_mock

  assert_success
}

@test "-r short flag: works as alias for --project-root" {
  setup_mock

  run bash "$TOOL_SH" -r "$FIXTURES"
  teardown_mock

  assert_success
}

@test "output is valid JSON" {
  setup_mock

  run bash "$TOOL_SH" --title "JSON Test"
  teardown_mock

  assert_success
  # Extract from the first '{' to the end (stderr is mixed in output)
  local json_only
  json_only="$(echo "$output" | sed -n '/^{/,$ p')"
  echo "$json_only" | python3 -m json.tool > /dev/null
}

@test "stderr info lines appear in output" {
  setup_mock

  run bash "$TOOL_SH" --project-root "$FIXTURES"
  teardown_mock

  assert_success
  # Wrapper execs python3 directly, so stderr goes to stderr (mixed in output)
  assert_output --partial "Scanning:"
}

@test "multiple flags combined: all work together" {
  setup_mock

  run bash "$TOOL_SH" \
    --project-root "$FIXTURES" \
    --component "Billing" \
    --title "Combined Test" \
    --subtitle "All flags"
  teardown_mock

  assert_success
  assert_output --partial '"title": "Combined Test"'
  assert_output --partial '"subtitle": "All flags"'
}

@test "exit code 0 on success with valid flags" {
  setup_mock

  run bash "$TOOL_SH" --title "Exit Test"
  teardown_mock

  assert_success
}

# =============================================================================
# Skill file validation
# =============================================================================

@test "use-case-map skill: SKILL.md exists" {
  [[ -f "$SKILLS_DIR/use-case-map/SKILL.md" ]]
}

@test "use-case-map skill: has YAML frontmatter with name" {
  run head -5 "$SKILLS_DIR/use-case-map/SKILL.md"
  assert_output --partial "name: devbot:use-case-map"
}

@test "use-case-map skill: has YAML frontmatter with description" {
  run head -10 "$SKILLS_DIR/use-case-map/SKILL.md"
  assert_output --partial "description:"
}

@test "app-map skill: SKILL.md exists" {
  [[ -f "$SKILLS_DIR/app-map/SKILL.md" ]]
}

@test "app-map skill: has YAML frontmatter with name" {
  run head -5 "$SKILLS_DIR/app-map/SKILL.md"
  assert_output --partial "name: devbot:app-map"
}

@test "app-map skill: has YAML frontmatter with description" {
  run head -10 "$SKILLS_DIR/app-map/SKILL.md"
  assert_output --partial "description:"
}

# =============================================================================
# AppMap asset tests
# =============================================================================

@test "app-map assets: AppMap.html exists" {
  [[ -f "$APP_MAP_ASSETS/AppMap.html" ]]
}

@test "app-map assets: AppMap.html starts with DOCTYPE" {
  run head -1 "$APP_MAP_ASSETS/AppMap.html"
  assert_output --partial "<!DOCTYPE html>"
}

@test "app-map assets: AppMap.schema.json exists" {
  [[ -f "$APP_MAP_ASSETS/AppMap.schema.json" ]]
}

@test "app-map assets: AppMap.schema.json is valid JSON" {
  python3 -m json.tool "$APP_MAP_ASSETS/AppMap.schema.json" > /dev/null
}

@test "app-map assets: schema defines required map types" {
  run python3 -c "
import json
with open('$APP_MAP_ASSETS/AppMap.schema.json') as f:
    s = json.load(f)
assert 'map' in str(s.get('\$defs', {}).get('baseItem', {}).get('properties', {}).get('type', {}).get('enum', []))
print('OK')
"
  assert_output "OK"
}

# =============================================================================
# UseCaseMap asset tests
# =============================================================================

@test "use-case-map assets: create-use-case-map.py exists" {
  [[ -f "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" ]]
}

@test "use-case-map assets: create-use-case-map.py is valid Python syntax" {
  python3 -m py_compile "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py"
}

@test "use-case-map assets: UseCaseMap.schema.json is valid JSON" {
  python3 -m json.tool "$MODULE_DIR/tools/UseCaseMap/UseCaseMap.schema.json" > /dev/null
}

@test "use-case-map assets: UseCaseMap.html exists" {
  [[ -f "$MODULE_DIR/tools/UseCaseMap/UseCaseMap.html" ]]
}

@test "use-case-map assets: schema defines required types" {
  run python3 -c "
import json
with open('$MODULE_DIR/tools/UseCaseMap/UseCaseMap.schema.json') as f:
    s = json.load(f)
types = s.get('definitions', {}).get('Unit', {}).get('properties', {}).get('type', {}).get('enum', [])
assert 'unit' in types
assert 'use-case' in types
assert 'command' in types
print('OK')
"
  assert_output "OK"
}

# =============================================================================
# Python script CLI behavior (smoke test with --help)
# =============================================================================

@test "create-use-case-map.py: --help exits 0" {
  run python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" --help

  assert_success
  assert_output --partial "usage:"
}

@test "create-use-case-map.py: --help mentions flags" {
  run python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" --help

  assert_output --partial "--project-root"
  assert_output --partial "--output"
  assert_output --partial "--component"
  assert_output --partial "--title"
  assert_output --partial "--subtitle"
  assert_output --partial "--copy-visualizer"
}

@test "create-use-case-map.py: exits 1 with non-existent project root" {
  run python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" \
    --project-root "/definitely/not/a/real/project/root"

  assert_failure
  assert_output --partial "Error: project root not found"
}

# =============================================================================
# audit-24 F1: conf/php configs ship with the module, tool fails loudly when
# the required arch config is missing, and the module carries no get-e branding.
# =============================================================================

@test "F1: conf/php config files ship with the module" {
  local conf_dir="$MODULE_DIR/conf/php"
  assert [ -f "$conf_dir/structure-explicit-architecture.php" ]
  assert [ -f "$conf_dir/http-clients-types.php" ]
  assert [ -f "$conf_dir/message-bus-dispatch-patterns.php" ]
  assert [ -f "$conf_dir/message-bus-types.php" ]
}

@test "F1: configs load without 'config not found' warning" {
  # A sandbox PHP project with composer.json; run the real tool and assert the
  # missing-config WARNING is gone (config resolution now works).
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/app"
  echo '{"require": {"php": ">=8.1"}}' > "${sandbox}/composer.json"

  run python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" \
    --project-root "$sandbox"

  rm -r "$sandbox"

  # exit 0 even with no PHP CLI (fallback path) — but never a config-not-found
  assert_success
  refute_output --partial "config not found"
  refute_output --partial "required config not found"
}

@test "F1: fails loudly when required arch config is missing" {
  local sandbox real_conf
  sandbox="$(mktemp -d)"
  real_conf="$MODULE_DIR/conf/php/structure-explicit-architecture.php"
  local moved="$MODULE_DIR/conf/php/structure-explicit-architecture.php.bak"

  mkdir -p "${sandbox}/app"
  echo '{"require": {"php": ">=8.1"}}' > "${sandbox}/composer.json"
  mv "$real_conf" "$moved"

  run python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" \
    --project-root "$sandbox"

  mv "$moved" "$real_conf"

  assert_failure
  assert_output --partial "ERROR: required config not found"
}

@test "F1: docs module carries no get-e branding" {
  run grep -rniE "get[-_]e" "$MODULE_DIR" --include='*.py' --include='*.sh' \
    --include='*.md' --include='*.php' --include='*.json' || true

  assert_output ""
}

@test "F1: empty map without PHP CLI is marked degraded, not reported as success" {
  # audit-27 FAIL-1: an empty map produced when PHP is unavailable must carry
  # a degraded marker so the MCP layer doesn't present it as success. Simulate
  # the container condition (docker present, daemon unreachable) by pointing
  # the tool at a PATH with no php and no usable docker.
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/app"
  echo '{"require": {"php": ">=8.1"}}' > "${sandbox}/composer.json"
  echo '<?php class Foo {}' > "${sandbox}/app/Foo.php"

  # A fake docker that always fails (rc 125, no daemon) so the tool's docker
  # PHP fallback degrades instead of succeeding.
  local bin_dir="${sandbox}/bin"
  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/docker" <<'SCRIPT'
#!/usr/bin/env bash
echo "Cannot connect to the Docker daemon" >&2
exit 125
SCRIPT
  chmod +x "${bin_dir}/docker"

  # A fake php that always fails (rc 127) so a host-installed php-cli (e.g.
  # /usr/bin/php, which shares a PATH dir with python3) cannot satisfy the
  # tool's local-PHP probe. Without this stub the test silently degrades into
  # a no-op when the host has php — the sandboxed PATH must fully control the
  # probe, never the host environment.
  cat > "${bin_dir}/php" <<'SCRIPT'
#!/usr/bin/env bash
echo "php: unavailable in test sandbox" >&2
exit 127
SCRIPT
  chmod +x "${bin_dir}/php"

  run env "PATH=${bin_dir}:$(dirname "$(command -v python3)")" \
    python3 "$MODULE_DIR/tools/UseCaseMap/create-use-case-map.py" \
    --project-root "$sandbox"

  rm -r "$sandbox"

  # Degraded marker present in the JSON (not a clean success) — assert on the
  # tool's own stdout.
  echo "$output" | python3 -c "
import json, sys
text = sys.stdin.read()
start = text.index('{')
d = json.loads(text[start:])
assert d.get('degraded') is True, d
assert 'degraded_reason' in d, d
print('DEGRADED:OK')
" | grep -qF 'DEGRADED:OK' || fail "degraded marker missing from output"
}
