#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/v2_handover_tests.bats
# Handing a project back from the opencode-v2 adapter.
#
# The v2 harness links its plugins as directory packages under
# .opencode/plugins/, and its PTY extension is the only thing in dev-bot that
# declares `bun-pty`. This harness never loads those packages, so init retires
# them — otherwise a v1 host keeps a plugin it cannot run and a dependency
# nothing uses.
#
# Sandbox pattern: strip init.sh at the `# ── main` marker so sourcing it only
# defines functions, then stub the progress helpers (see tui_config_tests.bats).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  HARNESS_DIR="${PROJECT_ROOT}/src/harnesses/opencode"

  SANDBOX_DIR="$(mktemp -d)"
  PLUGINS_DIR="${SANDBOX_DIR}/.opencode/plugins"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX_DIR}/src/_shared" "${PLUGINS_DIR}"
  sed '/^# ── main/,$d' "${HARNESS_DIR}/init.sh" > "${SANDBOX_DIR}/init.sh"

  cat > "${SANDBOX_DIR}/functions.sh" <<'FUNCTIONS_EOF'
_info()  { echo "INFO: $*"; }
_ok()    { echo "OK: $*"; }
_skip()  { echo "SKIP: $*"; }
_warn()  { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
FUNCTIONS_EOF

  cp "${SANDBOX_DIR}/functions.sh" "${SANDBOX_DIR}/src/_shared/functions.sh"
}

teardown() {
  rm -r -f "${SANDBOX_DIR}" 2>/dev/null || true
}

# Source the stripped init.sh with PROJECT_DIR pinned to the sandbox, so
# MODULE_DIR/OPENCODE_DIR all resolve inside it.
_source_init() {
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  set -- "${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/init.sh"
}

# A dev-bot-generated v2 plugin package: a real directory whose index.ts carries
# the shim marker.
_v2_package() {
  local name="$1"
  mkdir -p "${PLUGINS_DIR}/${name}"
  {
    printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)"
    printf 'export { default } from "%s"\n' "${SANDBOX_DIR}/src/harnesses/opencode-v2/hooks/${name}/index.ts"
  } > "${PLUGINS_DIR}/${name}/index.ts"
}

@test "v1 init retires the v2 harness's plugin packages" {
  _v2_package pty
  _v2_package on-hooks
  # A project's own package carries no marker and must survive.
  mkdir -p "${PLUGINS_DIR}/mine"
  printf 'export default {}\n' > "${PLUGINS_DIR}/mine/index.ts"

  _source_init
  run _sweep_v2_plugin_dirs

  assert_success
  assert_output --partial "Retired 2 opencode-v2 plugin package(s)"
  [ ! -e "${PLUGINS_DIR}/pty" ]
  [ ! -e "${PLUGINS_DIR}/on-hooks" ]
  [ -f "${PLUGINS_DIR}/mine/index.ts" ]
}

@test "a symlinked plugin directory is never removed" {
  # Removing through a link would delete whatever it names.
  mkdir -p "${SANDBOX_DIR}/outside/pkg"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    > "${SANDBOX_DIR}/outside/pkg/index.ts"
  ln -s "${SANDBOX_DIR}/outside/pkg" "${PLUGINS_DIR}/linked"

  _source_init
  run _sweep_v2_plugin_dirs

  assert_success
  refute_output --partial "Retired"
  [ -f "${SANDBOX_DIR}/outside/pkg/index.ts" ]
  [ -L "${PLUGINS_DIR}/linked" ]
}

@test "v1 init drops the bun-pty dependency dev-bot recorded as its own" {
  cat > "${SANDBOX_DIR}/.opencode/package.json" <<'JSON_EOF'
{
  "dependencies": {
    "bun-pty": "^0.4.10",
    "left-pad": "^1.0.0"
  }
}
JSON_EOF
  # The v2 init writes this record when it seeds the manifest, so the ownership
  # is stated rather than inferred from the dependency's name.
  printf 'bun-pty\n' > "${SANDBOX_DIR}/.opencode/.devbot-managed-deps"
  _v2_package pty

  _source_init
  run _sweep_v2_plugin_dirs

  assert_success
  assert_output --partial "Retired 1 opencode-v2 plugin package(s)"
  assert_output --partial "Dropped bun-pty"
  [ ! -e "${SANDBOX_DIR}/.opencode/.devbot-managed-deps" ]
  run python3 -c "
import json
d = json.load(open('${SANDBOX_DIR}/.opencode/package.json'))
assert d['dependencies'] == {'left-pad': '^1.0.0'}, d
print('kept the project dependency')
"
  assert_success
  assert_output --partial "kept the project dependency"
}

@test "a dependency the project declared is never touched" {
  # No record, so the manifest is the project's: a v2 PTY package coming and
  # going must not remove a dependency of the same name.
  cat > "${SANDBOX_DIR}/.opencode/package.json" <<'JSON_EOF'
{ "dependencies": { "bun-pty": "^0.4.10" } }
JSON_EOF
  _v2_package pty

  _source_init
  run _sweep_v2_plugin_dirs

  assert_success
  assert_output --partial "Retired 1 opencode-v2 plugin package(s)"
  refute_output --partial "Dropped"
  run python3 -c "
import json
d = json.load(open('${SANDBOX_DIR}/.opencode/package.json'))
assert d['dependencies'] == {'bun-pty': '^0.4.10'}, d
print('dependency kept')
"
  assert_success
  assert_output --partial "dependency kept"
}

@test "a second run has nothing left to retire" {
  cat > "${SANDBOX_DIR}/.opencode/package.json" <<'JSON_EOF'
{ "dependencies": { "bun-pty": "^0.4.10" } }
JSON_EOF
  printf 'bun-pty\n' > "${SANDBOX_DIR}/.opencode/.devbot-managed-deps"
  _v2_package pty

  _source_init
  run _sweep_v2_plugin_dirs
  assert_success
  assert_output --partial "Dropped bun-pty"

  run _sweep_v2_plugin_dirs
  assert_success
  refute_output --partial "Retired"
  refute_output --partial "Dropped"
}

@test "a project with no .opencode/package.json is left alone" {
  _v2_package pty

  _source_init
  run _sweep_v2_plugin_dirs
  assert_success
  refute_output --partial "Dropped"
  [ ! -e "${SANDBOX_DIR}/.opencode/package.json" ]
}
