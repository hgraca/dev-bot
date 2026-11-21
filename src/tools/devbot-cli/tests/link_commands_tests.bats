#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_commands_tests.bats
# _link_commands farms ONE LINK PER COMMAND, named after the command's full
# frontmatter `name`:
#   .agents/commands/devbot:<id>.md  ->  <module>/commands/<file>.md
#
# Both harnesses derive the slash command from the path, so the link's own name
# is the whole story: opencode joins path segments with `/` and claudecode joins
# the directory with `:`, so a flat `devbot:<id>.md` registers `/devbot:<id>` on
# both. A `devbot/` category dir would give opencode `/devbot/<id>` instead.
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
    FARM="${AGENTS_DIR}/commands"
    mkdir -p "${FARM}"
}

teardown() {
    rm -r -f "${SANDBOX}"
}

@test "_link_commands: links at the frontmatter name, not the filename" {
    printf -- '---\nname: devbot:audit\ndescription: x\n---\n' >"${MOD}/commands/audit.md"

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:audit.md" ]
    [ "$(readlink "${FARM}/devbot:audit.md")" = "${MOD}/commands/audit.md" ]
}

@test "_link_commands: a file whose basename differs from its name links at the name" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/odd/commands"
    printf -- '---\nname: devbot:renamed\n---\n' >"${DEV_BOT_ROOT}/src/agentic/odd/commands/original.md"

    _link_commands "${DEV_BOT_ROOT}/src/agentic/odd/"

    assert [ -L "${FARM}/devbot:renamed.md" ]
    refute [ -e "${FARM}/devbot:original.md" ]
}

@test "_link_commands: writes nothing when the command is already linked" {
    _link_commands "${MOD}/"
    local before
    before="$(readlink "${FARM}/devbot:demo.md")"

    run _link_commands "${MOD}/"

    assert_output --partial "already linked"
    [ "$(readlink "${FARM}/devbot:demo.md")" = "${before}" ]
}

@test "_link_commands: relinks a link this module owns that points at a stale path in it" {
    # Owned but dangling: the recorded target is inside the module, so it is ours
    # to re-point — including when the old file is already gone.
    ln -sf "${MOD}/commands/gone.md" "${FARM}/devbot:demo.md"

    _link_commands "${MOD}/"

    [ "$(readlink "${FARM}/devbot:demo.md")" = "${MOD}/commands/demo.md" ]
}

@test "_link_commands: prunes a command the module no longer ships" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/devbot:demo.md" ]

    rm -f "${MOD}/commands/demo.md"
    _link_commands "${MOD}/"

    # -e follows the link, and a dangling symlink reads as absent — assert the
    # link is gone, not its target.
    refute [ -L "${FARM}/devbot:demo.md" ]
    refute [ -e "${FARM}/devbot:demo.md" ]
}

@test "_link_commands: leaves a link pointing outside the module untouched" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:other\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/other.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    # demo ships only demo.md, so other.md is "unwanted" from demo's point of view.
    _link_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:other.md" ]
}

@test "_link_commands: leaves a real file at a command name untouched" {
    printf 'not a symlink\n' >"${FARM}/devbot:demo.md"

    run _link_commands "${MOD}/"

    assert_output --partial "is not a symlink"
    refute [ -L "${FARM}/devbot:demo.md" ]
    [ "$(cat "${FARM}/devbot:demo.md")" = "not a symlink" ]
}

@test "_link_commands: a module that ships no commands leaves another module's links alone" {
    # Seed a link from another module, or the assertion is about an empty farm and
    # passes even when the function does nothing.
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/devbot:demo.md" ]
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/bare"

    run _link_commands "${DEV_BOT_ROOT}/src/agentic/bare/"

    assert_success
    assert [ -L "${FARM}/devbot:demo.md" ]
}

@test "_link_commands: prunes when the module drops its whole commands dir" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/devbot:demo.md" ]

    # The directory is gone, so the link dangles and _link_target_path resolves
    # nothing — the case an early return left live.
    rm -r -f "${MOD}/commands"
    _link_commands "${MOD}/"

    refute [ -L "${FARM}/devbot:demo.md" ]
}

@test "_unlink_commands: prunes a dangling link whose directory is gone" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/devbot:demo.md" ]

    rm -r -f "${MOD}/commands"
    _unlink_commands "${MOD}/"

    refute [ -L "${FARM}/devbot:demo.md" ]
}

@test "_link_commands: a sibling directory sharing the prefix is out of scope" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/demo/commands-old"
    printf -- '---\nname: devbot:legacy\n---\n' >"${DEV_BOT_ROOT}/src/agentic/demo/commands-old/legacy.md"
    ln -sf "${DEV_BOT_ROOT}/src/agentic/demo/commands-old/legacy.md" "${FARM}/devbot:legacy.md"

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:legacy.md" ]
}

@test "_link_commands: a colliding name owned by another module is not replaced" {
    # The farm is shared, so a second module shipping the same command name must
    # not silently steal the link.
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:demo\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/demo.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    run _link_commands "${MOD}/"

    assert_output --partial "links outside this module"
    [ "$(readlink "${FARM}/devbot:demo.md")" = "${DEV_BOT_ROOT}/src/agentic/other/commands/demo.md" ]
}

@test "_unlink_commands: takes a disabled module's commands out of the farm" {
    _link_commands "${MOD}/"
    assert [ -L "${FARM}/devbot:demo.md" ]

    _unlink_commands "${MOD}/"

    refute [ -L "${FARM}/devbot:demo.md" ]
}

@test "_unlink_commands: leaves another module's command alone" {
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/other/commands"
    printf -- '---\nname: devbot:other\n---\n' >"${DEV_BOT_ROOT}/src/agentic/other/commands/other.md"
    _link_commands "${DEV_BOT_ROOT}/src/agentic/other/"

    _unlink_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:other.md" ]
}

@test "_link_modules: a disabled module's commands leave the farm" {
  # The regression this guards: _link_modules skipped a disabled module without
  # unlinking its commands, so its slash commands stayed invocable.
  _link_commands "${MOD}/"
  assert [ -L "${FARM}/devbot:demo.md" ]

  PROJECT_DIR="${SANDBOX}/project"
  # shellcheck disable=SC2317  # consumed by _link_modules
  _devbot_get_project_dir() { printf '.agents'; }
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() { printf '["demo"]'; }

  _link_modules

  refute [ -L "${FARM}/devbot:demo.md" ]
}

@test "_link_commands: a dangling link whose recorded target escapes the module is left alone" {
    # The recorded text starts with the module's commands dir, so a prefix check
    # accepts it — while the `..` components land outside the module entirely.
    # Pruning it would delete a foreign link.
    local escaped="${MOD}/commands/../../../../../outside/missing.md"
    ln -sf "${escaped}" "${FARM}/devbot:escaped.md"

    # Precondition: the target really is outside the module, and does not exist.
    [ ! -e "${escaped}" ]
    case "$(readlink "${FARM}/devbot:escaped.md")" in
        "${MOD}/commands/../.."*) ;; # recorded form starts inside, as intended
        *) fail "fixture does not start inside the module: $(readlink "${FARM}/devbot:escaped.md")" ;;
    esac

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:escaped.md" ]
}

@test "_link_commands: a dangling foreign link recorded through .. is not replaced" {
  # The link phase has the same hazard as the prune: a recorded target that
  # starts inside the module but escapes via `..` must not be considered ours.
  local escaped="${MOD}/commands/../../../../../outside/missing.md"
  ln -sf "${escaped}" "${FARM}/devbot:demo.md"

  run _link_commands "${MOD}/"

  assert_output --partial "links outside this module"
  [ "$(readlink "${FARM}/devbot:demo.md")" = "${escaped}" ]
}

@test "_link_commands: retires a legacy devbot/ category link and its empty dir" {
    # The pre-colon farm linked commands/devbot/<bare>.md, which opencode
    # registered as /devbot/<bare>. Left behind, both names stay invocable.
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    ln -sf "${MOD}/commands/demo.md" "${legacy}/demo.md"

    _link_commands "${MOD}/"

    assert [ -L "${FARM}/devbot:demo.md" ]
    refute [ -L "${legacy}/demo.md" ]
    refute [ -d "${legacy}" ]
}

@test "_link_commands: keeps a legacy link that points outside the install" {
    # A user's own command in the legacy dir is not ours to remove — and it is
    # what keeps the dir alive after every module has been retired.
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}" "${SANDBOX}/user-commands"
    printf 'mine\n' >"${SANDBOX}/user-commands/mine.md"
    ln -sf "${SANDBOX}/user-commands/mine.md" "${legacy}/mine.md"

    _link_commands "${MOD}/"

    assert [ -L "${legacy}/mine.md" ]
}

@test "_link_commands: retires an orphaned legacy link into the install root" {
    # A module that no longer exists (or an install that moved) leaves a link no
    # module's pass owns; it resolves into the install root, so it is ours.
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/gone/commands"
    printf -- '---\nname: devbot:vanished\n---\n' >"${DEV_BOT_ROOT}/src/agentic/gone/commands/vanished.md"
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    ln -sf "${DEV_BOT_ROOT}/src/agentic/gone/commands/vanished.md" "${legacy}/vanished.md"

    _link_commands "${MOD}/"

    refute [ -L "${legacy}/vanished.md" ]
    refute [ -d "${legacy}" ]
}

@test "_link_commands: retires an orphaned legacy link whose module dir is gone" {
    # The common upgrade case: the module was dropped, so the target's parent no
    # longer exists and the link resolves to nothing — it must still be retired,
    # or the old name stays invocable.
    mkdir -p "${DEV_BOT_ROOT}/src/agentic/gone/commands"
    printf -- '---\nname: devbot:vanished\n---\n' >"${DEV_BOT_ROOT}/src/agentic/gone/commands/vanished.md"
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    ln -sf "${DEV_BOT_ROOT}/src/agentic/gone/commands/vanished.md" "${legacy}/vanished.md"
    rm -rf "${DEV_BOT_ROOT}/src/agentic/gone"

    _link_commands "${MOD}/"

    refute [ -L "${legacy}/vanished.md" ]
    refute [ -d "${legacy}" ]
}

@test "_link_commands: keeps an orphaned dangling link recorded outside the install" {
    # The dangling fallback must not widen the rule into deleting a user's link.
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    ln -sf "${SANDBOX}/user-commands/gone.md" "${legacy}/gone.md"

    _link_commands "${MOD}/"

    assert [ -L "${legacy}/gone.md" ]
}

@test "_link_modules: reports a legacy dir it cannot empty, once per run" {
    # Silence here is how the old /devbot/<id> name stayed live on a project the
    # upgrade could not fully convert — and per-module reporting would repeat it
    # once for every module that passes.
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    printf 'mine\n' >"${legacy}/keep.md"

    PROJECT_DIR="${SANDBOX}/project"
    # shellcheck disable=SC2317  # consumed by _link_modules
    _devbot_get_project_dir() { printf '.agents'; }
    # shellcheck disable=SC2317
    _devbot_get_disabled_modules() { printf '[]'; }

    run _link_modules

    assert_output --partial "commands/devbot/ survives with:"
    [ "$(grep -c 'commands/devbot/ survives with:' <<< "$output")" -eq 1 ]
    [ "$(cat "${legacy}/keep.md")" = "mine" ]
}

@test "_link_commands: a command named without the devbot: prefix is not farmed" {
    # The link name is the frontmatter name verbatim now, so a typo would land a
    # top-level /audit in the user's namespace instead of inside ours.
    printf -- '---\nname: audit\n---\n' >"${MOD}/commands/unprefixed.md"

    run _link_commands "${MOD}/"

    assert_output --partial "not devbot:<id> — not farmed"
    refute [ -e "${FARM}/audit.md" ]
    refute [ -e "${FARM}/devbot:audit.md" ]
}

@test "_link_commands: a malformed devbot: name is not farmed" {
    # The prefix alone is not the contract: `devbot:` would farm a nameless
    # command, and a space cannot be typed as a slash command.
    printf -- '---\nname: devbot:\n---\n' >"${MOD}/commands/empty.md"
    printf -- '---\nname: devbot:has space\n---\n' >"${MOD}/commands/spaced.md"

    run _link_commands "${MOD}/"

    assert_output --partial "not devbot:<id> — not farmed"
    refute [ -e "${FARM}/devbot:.md" ]
    refute [ -e "${FARM}/devbot:has space.md" ]
}

@test "_unlink_commands: retires a disabled module's legacy category link too" {
    local legacy="${AGENTS_DIR}/commands/devbot"
    mkdir -p "${legacy}"
    ln -sf "${MOD}/commands/demo.md" "${legacy}/demo.md"

    _unlink_commands "${MOD}/"

    refute [ -L "${legacy}/demo.md" ]
    refute [ -d "${legacy}" ]
}
