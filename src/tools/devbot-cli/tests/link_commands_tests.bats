#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_commands_tests.bats
# _link_commands farms ONE LINK PER COMMAND, named after the command's frontmatter
# `name`:
#   .agents/commands/devbot/<name>.md  ->  <module>/commands/<file>.md
#
# Both harnesses resolve the same slash command from it: opencode reads the
# frontmatter `name:`, claudecode derives `<dir>:<file>` from the path — so the
# link name must equal the frontmatter name minus its `devbot:` prefix.
#
# It must also reconcile: prune what a module no longer ships, without touching
# another module's command or a user's own file — and a disabled module must take
# its commands out, or its slash commands stay invocable.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

    SANDBOX="$(mktemp -d)"
    export DEV_BOT_ROOT="${SANDBOX}/devbot"
    MOD="${DEV_BOT_ROOT}/src/agentic/demo"
    mkdir -p "${MOD}/commands"
    printf -- '---\nname: devbot:demo\n---\n' >"${MOD}/commands/demo.md"

    # shellcheck source=../functions.sh
    source "${MODULE_DIR}/functions.sh"
    AGENTS_DIR="${SANDBOX}/project/.agents"
    FARM="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${FARM}"
}

teardown() {
    rm -r -f "${SANDBOX}"
}

@test "_link_commands: links at the frontmatter name, not the filename" {
    printf -- '---\nname: devbot:audit\ndescription: x\n---\n' >"${MOD}/commands/audit.md"

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/audit.md" ]
    [ "$(readlink "${FARM}/audit.md")" = "${MOD}/commands/audit.md" ]
}

@test "_link_commands: a file whose basename differs from its name links at the name" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/odd/commands"
    printf -- '---\nname: devbot:renamed\n---\n' >"${DEV_BOT_ROOT}/src/agentic/odd/commands/original.md"

    _link_commands "${DEV_BOT_ROOT}/src/agentic/odd/"

    assert [ -L "${FARM}/renamed.md" ]
    refute [ -e "${FARM}/original.md" ]
}

@test "_link_commands: writes nothing when the command is already linked" {
    _link_commands "${MOD}/"
    local before
    before="$(readlink "${FARM}/demo.md")"

    run _link_commands "${MOD}/"

    assert_output --partial "already linked"
    [ "$(readlink "${FARM}/demo.md")" = "${before}" ]
}

@test "_link_commands: relinks a link this module owns that points at a stale path in it" {
    # Owned but dangling: the recorded target is inside the module, so it is ours
    # to re-point — including when the old file is already gone.
    ln -sf "${MOD}/commands/gone.md" "${FARM}/demo.md"

    _link_commands "${MOD}/"

    [ "$(readlink "${FARM}/demo.md")" = "${MOD}/commands/demo.md" ]
}

@test "_link_commands: prunes a command the module no longer ships" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/demo.md" ]

    rm -f "${MOD}/commands/demo.md"
    _link_commands "${MOD}/"

    # -e follows the link, and a dangling symlink reads as absent — assert the
    # link is gone, not its target.
    refute [ -L "${FARM}/demo.md" ]
    refute [ -e "${FARM}/demo.md" ]
}

@test "_link_commands: leaves a link pointing outside the module untouched" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:other\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/other.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    # demo ships only demo.md, so other.md is "unwanted" from demo's point of view.
    _link_commands "${MOD}/"

    assert [ -L "${FARM}/other.md" ]
}

@test "_link_commands: leaves a real file at a command name untouched" {
    printf 'not a symlink\n' >"${FARM}/demo.md"

    run _link_commands "${MOD}/"

    assert_output --partial "is not a symlink"
    refute [ -L "${FARM}/demo.md" ]
    [ "$(cat "${FARM}/demo.md")" = "not a symlink" ]
}

@test "_link_commands: a module that never shipped commands leaves the farm alone" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/bare"

    run _link_commands "${DEV_BOT_ROOT}/src/agentic/bare/"

    assert_success
    [ -z "$(ls -A "${FARM}")" ]
}

@test "_link_commands: prunes when the module drops its whole commands dir" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/demo.md" ]

    # The directory is gone, so the link dangles and _link_target_path resolves
    # nothing — the case an early return left live.
    rm -r -f "${MOD}/commands"
    _link_commands "${MOD}/"

    refute [ -L "${FARM}/demo.md" ]
}

@test "_unlink_commands: prunes a dangling link whose directory is gone" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/demo.md" ]

    rm -r -f "${MOD}/commands"
    _unlink_commands "${MOD}/"

    refute [ -L "${FARM}/demo.md" ]
}

@test "_link_commands: a sibling directory sharing the prefix is out of scope" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/demo/commands-old"
    printf -- '---\nname: devbot:legacy\n---\n' >"${DEV_BOT_ROOT}/src/agentic/demo/commands-old/legacy.md"
    ln -sf "${DEV_BOT_ROOT}/src/agentic/demo/commands-old/legacy.md" "${FARM}/legacy.md"

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/legacy.md" ]
}

@test "_link_commands: a colliding name owned by another module is not replaced" {
    # The farm is shared, so a second module shipping the same command name must
    # not silently steal the link.
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:demo\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/demo.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    run _link_commands "${MOD}/"

    assert_output --partial "links outside this module"
    [ "$(readlink "${FARM}/demo.md")" = "${DEV_BOT_ROOT}/src/agentic/other/commands/demo.md" ]
}

@test "_unlink_commands: takes a disabled module's commands out of the farm" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/demo.md" ]

    _unlink_commands "${MOD}/"

    refute [ -L "${FARM}/demo.md" ]
}

@test "_unlink_commands: leaves another module's command alone" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:other\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/other.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    _unlink_commands "${MOD}/"

    assert [ -L "${FARM}/other.md" ]
}

@test "_link_modules: a disabled module's commands leave the farm" {
  # The regression this guards: _link_modules skipped a disabled module without
  # unlinking its commands, so its slash commands stayed invocable.
  _link_commands "${MOD}/"
  assert [ -L "${FARM}/demo.md" ]

  PROJECT_DIR="${SANDBOX}/project"
  # shellcheck disable=SC2317  # consumed by _link_modules
  _devbot_get_project_dir() { printf '.agents'; }
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() { printf '["demo"]'; }

  _link_modules

  refute [ -L "${FARM}/demo.md" ]
}

@test "_link_commands: a dangling link whose recorded target escapes the module is left alone" {
    # The recorded text starts with the module's commands dir, so a prefix check
    # accepts it — while the `..` components land outside the module entirely.
    # Pruning it would delete a foreign link.
    local escaped="${MOD}/commands/../../../../../outside/missing.md"
    ln -sf "${escaped}" "${FARM}/escaped.md"

    # Precondition: the target really is outside the module, and does not exist.
    [ ! -e "${escaped}" ]
    case "$(readlink "${FARM}/escaped.md")" in
        "${MOD}/commands/../.."*) ;; # recorded form starts inside, as intended
        *) fail "fixture does not start inside the module: $(readlink "${FARM}/escaped.md")" ;;
    esac

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/escaped.md" ]
}

@test "_link_commands: a dangling foreign link recorded through .. is not replaced" {
  # The link phase has the same hazard as the prune: a recorded target that
  # starts inside the module but escapes via `..` must not be considered ours.
  local escaped="${MOD}/commands/../../../../../outside/missing.md"
  ln -sf "${escaped}" "${FARM}/demo.md"

  run _link_commands "${MOD}/"

  assert_output --partial "links outside this module"
  [ "$(readlink "${FARM}/demo.md")" = "${escaped}" ]
}
