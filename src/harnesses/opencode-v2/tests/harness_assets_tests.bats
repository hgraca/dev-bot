#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/harness_assets_tests.bats
# Modules DECLARE their harness assets (MCP wrappers, skill dirs); the
# harness creates them.
#
# Before this, each module wrote its own `.opencode/` symlink behind an
# `index("opencode")` gate, so every module skipped whenever another harness was
# selected and the MCP servers pointed at scripts that did not exist (exit 127).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  export V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared"
  export SKIP_CONFIRM=1
  export DEV_BOT_SKIP_PLUGIN_DEPS=1

  PROJECT="$(mktemp -d)"
  printf '{ "harness": "opencode-v2" }\n' > "${PROJECT}/.devbot.project.jsonc"
}

teardown() {
  rm -r "${PROJECT}"
}

@test "a declared MCP asset is linked by the harness" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # tools-mcp declares tools-mcp-serve.sh -> server/start-tools-mcp.sh
  assert [ -L "${PROJECT}/.opencode/tools-mcp-serve.sh" ]
  run readlink "${PROJECT}/.opencode/tools-mcp-serve.sh"
  assert_output --partial "src/agentic/tools-mcp/server/start-tools-mcp.sh"
}

@test "the k8s module's per-cluster launcher is linked" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # Every kctl-<cluster> runtime manifest runs {harness-dir}/kctl-mcp.sh: a
  # missing link turns every kctl server into exit 127, and nothing else
  # asserts that name.
  assert [ -L "${PROJECT}/.opencode/kctl-mcp.sh" ]
  run readlink "${PROJECT}/.opencode/kctl-mcp.sh"
  assert_output --partial "src/agentic/k8s/tools/kctl-mcp.sh"
}

@test "a declared shared asset resolves {devbot-root}" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # playwright and chrome-devtools share src/_shared/mcp-stdio-wrapper.js
  [[ -L "${PROJECT}/.opencode/playwright-mcp-wrapper.js" ]] || skip "playwright module not installed"
  run readlink "${PROJECT}/.opencode/playwright-mcp-wrapper.js"
  assert_output --partial "src/_shared/mcp-stdio-wrapper.js"
}

@test "a disabled module's asset is not linked" {
  printf '{ "harness": "opencode-v2", "modules": { "graphify": false } }\n' \
    > "${PROJECT}/.devbot.project.jsonc"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/graphify-serve.sh" ]
}

@test "a stale dev-bot asset link is pruned" {
  mkdir -p "${PROJECT}/.opencode"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/graphify/tools/start-graphify-mcp.sh" \
    "${PROJECT}/.opencode/some-retired-serve.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/some-retired-serve.sh" ]
}

@test "a user's own file in the harness dir is left alone" {
  mkdir -p "${PROJECT}/.opencode"
  printf '#!/bin/sh\n' > "${PROJECT}/.opencode/mine.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${PROJECT}/.opencode/mine.sh" ]
}

@test "the harness still starts an asset-backed MCP server command" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # The declared name must match what the canonical mcp.json references.
  run python3 - "${DEV_BOT_ROOT}/src/agentic/tools-mcp/mcp.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
command = " ".join(data["mcp"]["devbot-tools"]["command"])
assert "{harness-dir}/tools-mcp-serve.sh" in command, command
print("ok")
PYEOF
  assert_success
  assert_output "ok"
}

@test "a declared skill directory is linked into .opencode/skills" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # sentry declares {devbot-root}/storage/sentry/skills
  [[ -d "${DEV_BOT_ROOT}/storage/sentry/skills" ]] || skip "sentry skills not provisioned"
  assert [ -L "${PROJECT}/.opencode/skills/sentry" ]
  run readlink "${PROJECT}/.opencode/skills/sentry"
  assert_output --partial "storage/sentry/skills"
}

@test "a stale skill link is pruned" {
  mkdir -p "${PROJECT}/.opencode/skills"
  ln -sfn "${DEV_BOT_ROOT}/storage/sentry/skills" "${PROJECT}/.opencode/skills/retired"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/skills/retired" ]
}

@test "claudecode does not get per-module skill links" {
  printf '{ "harness": "claudecode" }
' > "${PROJECT}/.devbot.project.jsonc"
  # The claudecode harness flattens skills itself; the shared helper skips the
  # skills section for any harness dir other than .opencode.
  bash -c "source '${DEV_BOT_ROOT}/src/_shared/functions.sh'; _devbot_link_harness_assets '${PROJECT}' '.claude'" >/dev/null 2>&1
  refute [ -e "${PROJECT}/.claude/skills/sentry" ]
}

@test "a user's file at a declared asset name is not replaced" {
  mkdir -p "${PROJECT}/.opencode"
  printf '#!/bin/sh\necho mine\n' > "${PROJECT}/.opencode/tools-mcp-serve.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -L "${PROJECT}/.opencode/tools-mcp-serve.sh" ]
  run head -1 "${PROJECT}/.opencode/tools-mcp-serve.sh"
  assert_output "#!/bin/sh"
}

@test "the codebase-index EPIPE wrapper is linked and survives the sweep" {
  # Declared by the module, created by the harness, and spared by the
  # stale-link sweep because the declaration is what that sweep reads.
  # The module is only enabled when the codebase engine selects it, and the
  # developer's own config usually selects the other engine.
  local cfg
  cfg="$(mktemp)"
  printf '{"codebase_index_provider": "codebase-index"}\n' > "${cfg}"

  DEV_BOT_GLOBAL_CONFIG="${cfg}" bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert [ -L "${PROJECT}/.opencode/codebase-index-mcp-wrapper.js" ]

  run readlink "${PROJECT}/.opencode/codebase-index-mcp-wrapper.js"
  assert_output "${DEV_BOT_ROOT}/src/_shared/mcp-stdio-wrapper.js"

  DEV_BOT_GLOBAL_CONFIG="${cfg}" bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert [ -L "${PROJECT}/.opencode/codebase-index-mcp-wrapper.js" ]
  rm -f "${cfg}"
}

@test "a symlink outside dev-bot at a declared name is left alone" {
  mkdir -p "${PROJECT}/.opencode"
  ln -sfn "/tmp/elsewhere-script.sh" "${PROJECT}/.opencode/tools-mcp-serve.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run readlink "${PROJECT}/.opencode/tools-mcp-serve.sh"
  assert_output "/tmp/elsewhere-script.sh"
}

@test "one malformed manifest does not stop the others being linked" {
  # The declarations are read in one launch now, so a manifest that is not an
  # object must not take the batch down: an empty declaration list would make
  # the caller prune every link it had previously declared.
  local root="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${root}/src/agentic/good" "${root}/src/agentic/bad" "${root}/src/_shared"
  cp "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${root}/src/_shared/"
  printf '{"mcp":[{"name":"good-serve.sh","path":"serve.sh"}]}\n' \
    >"${root}/src/agentic/good/harness-assets.json"
  printf '["not","an","object"]\n' >"${root}/src/agentic/bad/harness-assets.json"
  printf '#!/bin/sh\n' >"${root}/src/agentic/good/serve.sh"

  run bash -c '
    set -uo pipefail
    DEV_BOT_ROOT="${1}"
    export DEV_BOT_ROOT
    source "${2}"
    _devbot_link_harness_assets "${3}" ".opencode" >/dev/null 2>&1
  ' _ "${root}" "${DEV_BOT_ROOT}/src/_shared/functions.sh" "${PROJECT}"

  # The good module still linked; the bad one simply contributed nothing.
  assert [ -L "${PROJECT}/.opencode/good-serve.sh" ]
}

@test "a manifest entry whose name is not a string is skipped, not fatal" {
  # The declarations are joined with a tab, so a non-string name raises in the
  # batch reader; it must cost only that entry, not every module's links.
  local root="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${root}/src/agentic/good" "${root}/src/agentic/mixed" "${root}/src/_shared"
  cp "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${root}/src/_shared/"
  printf '{"mcp":[{"name":"good-serve.sh","path":"serve.sh"}]}\n' \
    >"${root}/src/agentic/good/harness-assets.json"
  printf '{"mcp":[{"name":1,"path":"serve.sh"},{"name":"mixed-serve.sh","path":"serve.sh"}]}\n' \
    >"${root}/src/agentic/mixed/harness-assets.json"
  printf '#!/bin/sh\n' >"${root}/src/agentic/good/serve.sh"
  printf '#!/bin/sh\n' >"${root}/src/agentic/mixed/serve.sh"

  run bash -c '
    set -uo pipefail
    DEV_BOT_ROOT="${1}"
    export DEV_BOT_ROOT
    source "${2}"
    _devbot_link_harness_assets "${3}" ".opencode" >/dev/null 2>&1
  ' _ "${root}" "${DEV_BOT_ROOT}/src/_shared/functions.sh" "${PROJECT}"

  # The well-formed entry beside the malformed one still links.
  assert [ -L "${PROJECT}/.opencode/good-serve.sh" ]
  assert [ -L "${PROJECT}/.opencode/mixed-serve.sh" ]
}
