#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_tools_tests.bats
# _link_tools farms ONE LINK PER *.mcp.sh at a flat name:
#   .agents/tools/<name>.mcp.sh  ->  <module>/tools/**/<name>.mcp.sh
#
# It must reconcile like the command farm — prune what a module no longer ships,
# leave a foreign link alone — and a disabled module must take its tools out.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

    SANDBOX="$(mktemp -d)"
    export DEV_BOT_ROOT="${SANDBOX}/devbot"
    MOD="${DEV_BOT_ROOT}/src/agentic/demo"
    mkdir -p "${MOD}/tools"
    printf '#!/usr/bin/env bash\n' >"${MOD}/tools/run.mcp.sh"

    # shellcheck source=../functions.sh
    source "${MODULE_DIR}/functions.sh"
    AGENTS_DIR="${SANDBOX}/project/.agents"
    FARM="${AGENTS_DIR}/tools"
    mkdir -p "${FARM}"
}

teardown() {
    rm -r -f "${SANDBOX}"
}

@test "_link_tools: links an mcp tool at its basename" {
    _link_tools "${MOD}/"

    assert [ -L "${FARM}/run.mcp.sh" ]
    [ "$(readlink "${FARM}/run.mcp.sh")" = "${MOD}/tools/run.mcp.sh" ]
}

@test "_link_tools: ignores non-mcp helper scripts" {
    printf '#!/usr/bin/env bash\n' >"${MOD}/tools/helper.sh"
    printf 'console.log(1)\n' >"${MOD}/tools/helper.ts"

    _link_tools "${MOD}/"

    refute [ -e "${FARM}/helper.sh" ]
    refute [ -e "${FARM}/helper.ts" ]
}

@test "_link_tools: links a tool nested up to three levels down" {
    mkdir -p "${MOD}/tools/deep/inner"
    printf '#!/usr/bin/env bash\n' >"${MOD}/tools/deep/inner/nested.mcp.sh"

    _link_tools "${MOD}/"

    assert [ -L "${FARM}/nested.mcp.sh" ]
}

@test "_link_tools: writes nothing when already linked" {
    _link_tools "${MOD}/"

    run _link_tools "${MOD}/"

    assert_output --partial "already linked"
}

@test "_link_tools: relinks an owned link that points at a stale path" {
    ln -sf "${MOD}/tools/gone.mcp.sh" "${FARM}/run.mcp.sh"

    _link_tools "${MOD}/"

    [ "$(readlink "${FARM}/run.mcp.sh")" = "${MOD}/tools/run.mcp.sh" ]
}

@test "_link_tools: a colliding name owned by another module is not replaced" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/tools"
    printf '#!/usr/bin/env bash\n' >"${DEV_BOT_ROOT}/src/agentic/other/tools/run.mcp.sh"
    _link_tools "${DEV_BOT_ROOT}/src/agentic/other/"

    run _link_tools "${MOD}/"

    assert_output --partial "links outside this module"
    [ "$(readlink "${FARM}/run.mcp.sh")" = "${DEV_BOT_ROOT}/src/agentic/other/tools/run.mcp.sh" ]
}

@test "_link_tools: leaves a real file at a tool name untouched" {
    printf 'not a symlink\n' >"${FARM}/run.mcp.sh"

    run _link_tools "${MOD}/"

    assert_output --partial "is not a symlink"
    refute [ -L "${FARM}/run.mcp.sh" ]
}

@test "_link_tools: prunes a tool the module no longer ships" {
    _link_tools "${MOD}/"
    assert [ -L "${FARM}/run.mcp.sh" ]

    rm -f "${MOD}/tools/run.mcp.sh"
    _link_tools "${MOD}/"

    refute [ -L "${FARM}/run.mcp.sh" ]
}

@test "_link_tools: prunes when the module drops its whole tools dir" {
    _link_tools "${MOD}/"
    assert [ -L "${FARM}/run.mcp.sh" ]

    rm -r -f "${MOD}/tools"
    _link_tools "${MOD}/"

    refute [ -L "${FARM}/run.mcp.sh" ]
}

@test "_link_tools: a sibling directory sharing the prefix is out of scope" {
    mkdir -p "${MOD}/tools-old"
    printf '#!/usr/bin/env bash\n' >"${MOD}/tools-old/legacy.mcp.sh"
    ln -sf "${MOD}/tools-old/legacy.mcp.sh" "${FARM}/legacy.mcp.sh"

    _link_tools "${MOD}/"

    assert [ -L "${FARM}/legacy.mcp.sh" ]
}

@test "_unlink_tools: takes a disabled module's tools out of the farm" {
    _link_tools "${MOD}/"
    assert [ -L "${FARM}/run.mcp.sh" ]

    _unlink_tools "${MOD}/"

    refute [ -L "${FARM}/run.mcp.sh" ]
}

@test "_unlink_tools: removes its own tools and leaves another module's alone" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/tools"
    printf '#!/usr/bin/env bash\n' >"${DEV_BOT_ROOT}/src/agentic/other/tools/other.mcp.sh"
    _link_tools "${DEV_BOT_ROOT}/src/agentic/other/"
    _link_tools "${MOD}/"
    assert [ -L "${FARM}/run.mcp.sh" ]

    _unlink_tools "${MOD}/"

    # Both halves: a no-op unlink would leave run.mcp.sh behind.
    refute [ -L "${FARM}/run.mcp.sh" ]
    assert [ -L "${FARM}/other.mcp.sh" ]
}

@test "_link_modules: a disabled module's tools leave the farm" {
    _link_tools "${MOD}/"
    assert [ -L "${FARM}/run.mcp.sh" ]

    PROJECT_DIR="${SANDBOX}/project"
    # shellcheck disable=SC2317  # consumed by _link_modules
    _devbot_get_project_dir() { printf '.agents'; }
    # shellcheck disable=SC2317
    _devbot_get_disabled_modules() { printf '["demo"]'; }

    _link_modules

    refute [ -L "${FARM}/run.mcp.sh" ]
}

@test "_link_modules: a collided name survives when the owning module is disabled" {
  # Enabled module links first and refuses the disabled module's link; the
  # disabled module's unlink must not then remove the enabled module's link.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/zzz/tools"
  printf '#!/usr/bin/env bash\n' >"${DEV_BOT_ROOT}/src/agentic/zzz/tools/run.mcp.sh"
  _link_tools "${DEV_BOT_ROOT}/src/agentic/zzz/"
  assert [ -L "${FARM}/run.mcp.sh" ]

  PROJECT_DIR="${SANDBOX}/project"
  # shellcheck disable=SC2317  # consumed by _link_modules
  _devbot_get_project_dir() { printf '.agents'; }
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() { printf '["zzz"]'; }

  _link_modules

  # The enabled module owns the name now — not left absent.
  [ "$(readlink "${FARM}/run.mcp.sh")" = "${MOD}/tools/run.mcp.sh" ]
}
