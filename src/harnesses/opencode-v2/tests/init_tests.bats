#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_tests.bats
# Tests init.sh / reset.sh: config seeding, plugin linking, the handover sweep,
# v1 config migration, and the harness gate.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  export V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared"
  export SKIP_CONFIRM=1
  # Keep the suite offline and fast; the install path is exercised by hand.
  export DEV_BOT_SKIP_PLUGIN_DEPS=1

  PROJECT="$(mktemp -d)"
  printf '{ "harness": "opencode-v2" }\n' > "${PROJECT}/.devbot.project.jsonc"
  CONFIG="${PROJECT}/opencode.jsonc"
  HELPER="${MODULE_DIR}/lib/v2config.py"
}

teardown() {
  rm -rf "${PROJECT}"
}

v2() {
  python3 "${HELPER}" "$@"
}

@test "init seeds the v2 config shapes" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  [ -f "${CONFIG}" ]
  run v2 has-legacy "${CONFIG}"
  assert_failure
  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "external_directory"'
}

@test "init is byte-idempotent across repeated runs" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local first
  first="$(md5sum "${CONFIG}" | cut -d' ' -f1)"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert_equal "$(md5sum "${CONFIG}" | cut -d' ' -f1)" "${first}"
}

@test "init links each plugin as a directory and registers it" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local name entry
  for name in on-hooks mcp-sync pty; do
    assert [ -d "${PROJECT}/.opencode/plugins/${name}" ]
    entry="${PROJECT}/.opencode/plugins/${name}/index.ts"
    # MUST be a real file: v2 skips a symlinked plugin entry silently.
    assert [ -f "${entry}" ]
    refute [ -L "${entry}" ]
    grep -q "dev-bot: generated opencode-v2 plugin shim" "${entry}"
    grep -q 'export { default } from ' "${entry}"
  done
  run v2 get "${CONFIG}" plugins
  assert_output --partial 'plugins/on-hooks'
  assert_output --partial 'plugins/pty'
}


@test "init leaves root-level module assets alone" {
  # The sweep must only touch the harness-owned farms: .opencode/ root also
  # holds module MCP wrappers, and deleting those breaks them with exit 127.
  mkdir -p "${PROJECT}/.opencode"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/tools-mcp/server/start-tools-mcp.sh" \
    "${PROJECT}/.opencode/tools-mcp-serve.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/tools-mcp-serve.sh" ]
}

@test "every plugin directory carries a package.json" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local name
  for name in on-hooks mcp-sync pty; do
    assert [ -f "${PROJECT}/.opencode/plugins/${name}/package.json" ]
    python3 -c "
import json,sys
d=json.load(open('${PROJECT}/.opencode/plugins/${name}/package.json'))
assert d['name'].startswith('devbot-'), d
assert 'exports' in d, d
"
  done
}

@test "init pins local MCP servers to the project directory" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # A local server carried over from a migrated v1 config has no cwd, and v2
  # spawns it outside the project — its relative wrapper path then exits 127.
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["bash","x.sh"]}'

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run python3 "${MODULE_DIR}/lib/v2config.py" get "${CONFIG}" mcp.servers.demo.cwd
  assert_success
  assert_output --partial "${PROJECT}"
}

@test "init sweeps a dev-bot symlink and keeps user files" {
  mkdir -p "${PROJECT}/.opencode/plugins"
  # A target that does not exist: readlink -f cannot resolve it.
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards/hooks/opencode/gone.ts" "${PROJECT}/.opencode/plugins/gone.ts"
  echo user > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/plugins/gone.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init drops the emptied v1 plugin farms" {
  mkdir -p "${PROJECT}/.opencode/tui-plugins"
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/pty-monitor" "${PROJECT}/.opencode/tui-plugins/pty-monitor"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -d "${PROJECT}/.opencode/tui-plugins" ]
}

@test "init migrates a v1 config and leaves a backup" {
  cat > "${CONFIG}" <<'EOF'
{
  "model": "p/m",
  "plugin": ["a-plugin", ["./x.ts", {"k": 1}], ".opencode/plugins/on-hooks.ts", "opencode-pty@0.3.6"],
  "permission": {"bash": {"*": "allow", "sudo *": "ask"}, "edit": "allow", "list": "allow"},
  "agent": {"devbot": {"model": "p/m", "variant": "high"}, "plan": {"disable": true}},
  "provider": {"p": {"npm": "@x/y", "options": {"t": 1}}},
  "mcp": {"s": {"type": "local", "command": ["c"], "enabled": false}},
  "lsp": true
}
EOF
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success

  assert [ -f "${CONFIG}.pre-v2.bak" ]
  run v2 has-legacy "${CONFIG}"
  assert_failure

  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "shell"'
  assert_output --partial '"resource": "sudo *"'
  refute_output --partial '"action": "list"'

  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"disabled": true'
  refute_output --partial '"enabled"'

  run v2 get "${CONFIG}" agents
  assert_output --partial '"model": "p/m#high"'
  assert_output --partial '"disabled": true'

  run v2 get "${CONFIG}" providers
  assert_output --partial '"package": "@x/y"'
  assert_output --partial '"settings"'
}

@test "reset removes dev-bot symlinks and keeps user files" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # .opencode/agents is a delegated symlink, so plant the link in the
  # plugin dir — a real directory that reset walks.
  mkdir -p "${PROJECT}/.opencode/plugins"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards" "${PROJECT}/.opencode/plugins/guards"
  echo user > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/plugins/guards" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "reset leaves the tree untouched when opencode-v2 is not selected" {
  printf '{ "harness": "opencode" }\n' > "${PROJECT}/.devbot.project.jsonc"
  mkdir -p "${PROJECT}/.opencode/agents"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards" "${PROJECT}/.opencode/agents/guards"

  run bash "${MODULE_DIR}/reset.sh" "${PROJECT}"
  assert_success
  assert [ -L "${PROJECT}/.opencode/agents/guards" ]
}

@test "reset keeps a user's broken symlink" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins"
  ln -sfn "/nonexistent/user-target" "${PROJECT}/.opencode/plugins/mine"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/plugins/mine" ]
}

@test "init keeps a user's own plugin entry file" {
  mkdir -p "${PROJECT}/.opencode/plugins/tui-defaults"
  printf 'export default {}\n' > "${PROJECT}/.opencode/plugins/tui-defaults/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run cat "${PROJECT}/.opencode/plugins/tui-defaults/index.ts"
  assert_output "export default {}"
}

@test "a v1-only plugin does not suppress the module's MCP under v2" {
  # codebase-index ships plugin.opencode.json only; that plugin does not load
  # under 2.x, so its canonical MCP must be registered instead.
  local cfg
  cfg="$(mktemp)"
  printf '{"codebase_index_provider": "codebase-index"}\n' > "${cfg}"

  DEV_BOT_GLOBAL_CONFIG="${cfg}" bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run v2 get "${CONFIG}" mcp
  assert_success
  assert_output --partial '"codebase-index"'
  rm -f "${cfg}"
}

@test "init does not link the retired TUI parts" {
  # opencode 2.3 rejects their module shape, so shipping them only produced
  # "Invalid V2 TUI plugin module" on every start.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/tui-defaults" ]
  [ ! -e "${PROJECT}/.opencode/plugins/provider-ttft" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "tui-defaults"
  refute_output --partial "provider-ttft"
}

@test "init retires a plugin package this build no longer ships" {
  # An earlier init generated it (marker present) and listed it in the config.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins/old-plugin"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    "export { default } from \"/nope\"" > "${PROJECT}/.opencode/plugins/old-plugin/index.ts"
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/old-plugin" >/dev/null

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/old-plugin" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "old-plugin"
}

@test "init keeps a user's own plugin package" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  printf 'export default { id: "mine", setup() {} }\n' \
    > "${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${PROJECT}/.opencode/plugins/mine/index.ts" ]
}

@test "init removes the v1 harness's plugin links" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/hooks/on-hooks.ts" \
    "${PROJECT}/.opencode/plugins/on-hooks.ts"
  printf 'export default {}\n' > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ ! -e "${PROJECT}/.opencode/plugins/on-hooks.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init never removes through a symlinked plugin directory" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local outside
  outside="$(mktemp -d)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    > "${outside}/index.ts"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/elsewhere"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${outside}/index.ts" ]
  rm -r -f "${outside}"
}

@test "init never treats a symlinked entry file as a generated package" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local outside
  outside="$(mktemp)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${outside}"
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -d "${PROJECT}/.opencode/plugins/mine" ]
  assert [ -f "${outside}" ]
  rm -f "${outside}"
}
