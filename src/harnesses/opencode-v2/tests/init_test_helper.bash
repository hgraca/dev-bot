#!/usr/bin/env bats
# shellcheck disable=SC2034  # fixtures consumed by the tests that load this
# =============================================================================
# src/harnesses/opencode-v2/tests/init_test_helper.bash
# Shared setup, teardown and scenarios for the opencode-v2 init/reset tests.
#
# Tests init.sh / reset.sh: config seeding, plugin linking, the handover sweep,
# v1 config migration, the skill farm and the harness gate.
#
# Split from init_tests.bats: bats parallelises across files only, and that one
# file backed the suite's wall clock. It is now four themed files that all load
# this, so the setup and the scenario seeds are written once.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  export DEV_BOT_ROOT
  export V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared"
  export SKIP_CONFIRM=1

  PROJECT="$(mktemp -d)"
  SCRATCH="${PROJECT}"
  printf '{ "harness": "opencode-v2" }\n' >"${PROJECT}/.devbot.project.jsonc"
  CONFIG="${PROJECT}/opencode.jsonc"
  HELPER="${MODULE_DIR}/lib/v2config.py"
}

teardown() {
  # Only the directory setup() made is ours. A scenario tree lives under
  # BATS_FILE_TMPDIR and is shared by the tests that assert on it.
  rm -rf "${SCRATCH}"
}

v2() {
  python3 "${HELPER}" "$@"
}

# ── Scenarios: one init run per distinct input ───────────────────────────────
# The mechanism lives in src/_shared/tests/lib/scenario.bash, which every test
# file loads before this one. A scenario is one project tree init has been run
# against exactly once per file; the case below is the input that makes it
# distinct, so the whole scenario set is visible in one place.
_build_init_scenario() {
  local name="$1" dir="$2"
  printf '{ "harness": "opencode-v2" }\n' >"${dir}/.devbot.project.jsonc"
  case "${name}" in
    default) ;;
    root-asset) _seed_root_asset "${dir}" ;;
    v2-farm) _seed_v2_farm "${dir}" ;;
    pty-package) _seed_pty_package "${dir}" ;;
    existing-package) _seed_existing_package "${dir}" ;;
    sweep) _seed_sweep "${dir}" ;;
    tui-farms) _seed_tui_farms "${dir}" ;;
    tui-json) _seed_tui_json "${dir}" ;;
    user-plugin-entry) _seed_user_plugin_entry "${dir}" ;;
    skill-farm) _seed_skill_farm "${dir}" ;;
    farm-prune) _seed_farm_prune "${dir}" ;;
    farm-external) _seed_farm_external "${dir}" ;;
    *) fail "unknown scenario '${name}'" ;;
  esac
  bash "${MODULE_DIR}/init.sh" "${dir}"
}

# scenario <name> — the shared tree, for tests that only read it.
scenario() {
  scenario_once "$1" _build_init_scenario
  PROJECT="${SCENARIO}"
  CONFIG="${PROJECT}/opencode.jsonc"
}

# scenario_copy <name> — this test's own copy, for tests that mutate first.
scenario_copy() {
  scenario_copy_once "$1" _build_init_scenario
  PROJECT="${SCENARIO}"
  CONFIG="${PROJECT}/opencode.jsonc"
}

# init_said <name> — the scenario's captured output in $output/$status.
init_said() { scenario_output "$1"; }

# ── Seeds: the pre-state that defines a scenario ─────────────────────────────
# Each one is exactly what the tests used to build before their own init run.

_seed_root_asset() {
  mkdir -p "$1/.opencode"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/tools-mcp/server/start-tools-mcp.sh" \
    "$1/.opencode/tools-mcp-serve.sh"
}

_seed_v2_farm() {
  mkdir -p "$1/.opencode/v2/plugins"
}

_seed_pty_package() {
  local dir="$1/.opencode/plugins/pty"
  mkdir -p "${dir}"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" >"${dir}/index.ts"
  printf '{"name":"devbot-pty","version":"0.0.0","type":"module","main":"./index.ts","exports":{".":"./index.ts"}}\n' >"${dir}/package.json"
}

_seed_existing_package() {
  mkdir -p "$1/.opencode"
  printf '{ "dependencies": { "bun-pty": "^0.4.10" } }\n' >"$1/.opencode/package.json"
}

_seed_sweep() {
  mkdir -p "$1/.opencode/plugins"
  # A target that does not exist: readlink -f cannot resolve it.
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards/hooks/opencode/gone.ts" "$1/.opencode/plugins/gone.ts"
  echo user >"$1/.opencode/plugins/mine.ts"
}

_seed_tui_farms() {
  mkdir -p "$1/.opencode/tui-plugins"
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/pty-monitor" "$1/.opencode/tui-plugins/pty-monitor"
}

_seed_tui_json() {
  mkdir -p "$1/.opencode"
  cat >"$1/.opencode/tui.json" <<'EOF'
{
  "$schema": "https://opencode.ai/tui.json",
  "plugin_enabled": { "internal:sidebar-context": false },
  "plugin": [
    "opencode-tabs@0.3.0",
    "./tui-plugins/pty-monitor/index.ts",
    "./tui-plugins/tui-defaults/index.ts",
    "./tui-plugins/provider-ttft/index.ts",
    "opencode-mine@1.0.0"
  ]
}
EOF
}

_seed_user_plugin_entry() {
  mkdir -p "$1/.opencode/plugins/tui-defaults"
  printf 'export default {}\n' >"$1/.opencode/plugins/tui-defaults/index.ts"
}

_seed_skill_farm() {
  mkdir -p "$1/.agents/skills/devbot/git/devbot:git-commits"
  printf -- '---\nname: devbot:git-commits\n---\n' \
    >"$1/.agents/skills/devbot/git/devbot:git-commits/SKILL.md"
  mkdir -p "$1/.agents/skills/mattpocock-grilling"
  printf -- '---\nname: grilling\n---\n' >"$1/.agents/skills/mattpocock-grilling/SKILL.md"
}

_seed_farm_prune() {
  mkdir -p "$1/.agents/skills/devbot" "$1/.agents/skills/gone"
}

_seed_farm_external() {
  mkdir -p "$1/.agents/skills"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/git/skills" "$1/.agents/skills/probe-external"
}
