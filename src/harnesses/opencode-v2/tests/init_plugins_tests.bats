#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_plugins_tests.bats
# plugin packages: linking, keeping and retiring.
#
# A dev-bot shim is recognised by its marker, a user's package is never claimed,
# and reset removes only what dev-bot owns.
#
# Split from init_tests.bats: bats parallelises across files only, and that file
# backed the suite's wall clock. Scenarios and seeds come from init_test_helper.
# =============================================================================

load "${BATS_TEST_DIRNAME}/../../../_shared/tests/lib/scenario"
load 'init_test_helper'

@test "reset removes dev-bot symlinks and keeps user files" {
  scenario_copy default
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
  scenario_copy default
  mkdir -p "${PROJECT}/.opencode/plugins"
  ln -sfn "/nonexistent/user-target" "${PROJECT}/.opencode/plugins/mine"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/plugins/mine" ]
}

@test "init keeps a user's own plugin entry file" {
  scenario user-plugin-entry

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

@test "init links no TUI part at all" {
  # tui-defaults is still on the pre-2.3 API (its kv surface has no 2.3
  # equivalent), and provider-ttft was retired once 2.3's built-in prompt footer
  # started reporting ttft. This harness ships server plugins only.
  scenario default

  [ ! -e "${PROJECT}/.opencode/plugins/tui-defaults" ]
  [ ! -e "${PROJECT}/.opencode/plugins/provider-ttft" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "tui-defaults"
  refute_output --partial "provider-ttft"
}

@test "init retires the TTFT package an earlier build shipped" {
  scenario_copy default
  mkdir -p "${PROJECT}/.opencode/plugins/provider-ttft"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    "export { default } from \"/nope\"" >"${PROJECT}/.opencode/plugins/provider-ttft/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/provider-ttft" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "provider-ttft"
}

@test "init retires a plugin package this build no longer ships" {
  # An earlier init generated it (marker present) and listed it in the config.
  scenario_copy default
  mkdir -p "${PROJECT}/.opencode/plugins/old-plugin"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    "export { default } from \"/nope\"" >"${PROJECT}/.opencode/plugins/old-plugin/index.ts"
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/old-plugin" >/dev/null

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/old-plugin" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "old-plugin"
}

@test "init keeps a user's own plugin package" {
  scenario_copy default
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  printf 'export default { id: "mine", setup() {} }\n' \
    >"${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${PROJECT}/.opencode/plugins/mine/index.ts" ]
}

@test "init removes the v1 harness's plugin links" {
  scenario_copy default
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/hooks/on-hooks.ts" \
    "${PROJECT}/.opencode/plugins/on-hooks.ts"
  printf 'export default {}\n' >"${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ ! -e "${PROJECT}/.opencode/plugins/on-hooks.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init never removes through a symlinked plugin directory" {
  scenario_copy default
  local outside
  outside="$(mktemp -d)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    >"${outside}/index.ts"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/elsewhere"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${outside}/index.ts" ]
  rm -r -f "${outside}"
}

@test "init never treats a symlinked entry file as a generated package" {
  scenario_copy default
  local outside
  outside="$(mktemp)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" >"${outside}"
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -d "${PROJECT}/.opencode/plugins/mine" ]
  assert [ -f "${outside}" ]
  rm -f "${outside}"
}

@test "reset prunes a disabled module's servers whose keys differ from its name" {
  scenario_copy default

  # The k8s module's manifests are `k8s-<cluster>.mcp.json` (the filename keeps
  # the module's name, which is how a disabled module's manifests are found)
  # while the server keys inside them are `kctl-<key>`. Disabling the module
  # must take both, or a live server outlives the access it points at.
  printf '{ "harness": "opencode-v2", "modules": { "k8s": false } }\n' \
    > "${PROJECT}/.devbot.project.jsonc"
  printf '%s\n' '{"kctl-demo": {"type": "local", "command": ["bash", "-c", "true"]}}' \
    > "${PROJECT}/.opencode/k8s-demo.mcp.json"
  v2 merge-mcp "${CONFIG}" kctl-demo '{"type":"local","command":["bash","-c","true"]}'
  # An unrelated server is not swept.
  v2 merge-mcp "${CONFIG}" other '{"type":"local","command":["bash","-c","true"]}'

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/k8s-demo.mcp.json" ]
  run v2 get "${CONFIG}" mcp.servers
  assert_success
  refute_output --partial '"kctl-demo"'
  assert_output --partial '"other"'
}

@test "reset of a disabled module's prefixed servers is byte-idempotent" {
  scenario_copy default

  printf '{ "harness": "opencode-v2", "modules": { "k8s": false } }\n' \
    > "${PROJECT}/.devbot.project.jsonc"
  printf '%s\n' '{"kctl-demo": {"type": "local", "command": ["bash", "-c", "true"]}}' \
    > "${PROJECT}/.opencode/k8s-demo.mcp.json"
  v2 merge-mcp "${CONFIG}" kctl-demo '{"type":"local","command":["bash","-c","true"]}'

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null
  local after_first
  after_first="$(cat "${CONFIG}")"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  assert_equal "$(cat "${CONFIG}")" "${after_first}"
}

@test "reset prunes a kctl key whose manifest is already gone" {
  scenario_copy default

  # A removed manifest leaves the merged key behind. It is not named after the
  # module, so only the prefix declared in mcp.dynamic.json finds it.
  printf '{ "harness": "opencode-v2", "modules": { "k8s": false } }\n' \
    > "${PROJECT}/.devbot.project.jsonc"
  v2 merge-mcp "${CONFIG}" kctl-demo '{"type":"local","command":["bash","-c","true"]}'
  v2 merge-mcp "${CONFIG}" other '{"type":"local","command":["bash","-c","true"]}'

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  run v2 get "${CONFIG}" mcp.servers
  assert_success
  refute_output --partial '"kctl-demo"'
  assert_output --partial '"other"'
}
