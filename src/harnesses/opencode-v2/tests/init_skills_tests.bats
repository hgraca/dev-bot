#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_skills_tests.bats
# the skill farm wired into the directory the host scans.
#
# A 2.x host never discovers <devbot_dir>/skills, so every farm entry has to be
# linked into .opencode/skills — and a link pointing outside the farm is not
# dev-bot's to remove.
#
# Split from init_tests.bats: bats parallelises across files only, and that file
# backed the suite's wall clock. Scenarios and seeds come from init_test_helper.
# =============================================================================

load "${BATS_TEST_DIRNAME}/../../../_shared/tests/lib/scenario"
load 'init_test_helper'

# ── Skill farm wiring (audit-01 FAIL-4) ───────────────────────────────────────
# A 2.x host scans ONLY <.opencode/skill(s)>; it never discovers <devbot_dir>/
# skills. The farm therefore has to be linked into .opencode/skills, one link per
# farm entry, or every devbot skill is unloadable.

@test "init wires the skill farm into .opencode/skills, one link per entry" {
  scenario skill-farm

  # Each farm entry is reachable through the directory the host scans.
  assert [ -L "${PROJECT}/.opencode/skills/devbot" ]
  [ "$(readlink "${PROJECT}/.opencode/skills/devbot")" = "${PROJECT}/.agents/skills/devbot" ]
  assert [ -L "${PROJECT}/.opencode/skills/mattpocock-grilling" ]
  # The id a 2.x host derives is the SKILL.md parent directory: devbot:<skill>.
  assert [ -f "${PROJECT}/.opencode/skills/devbot/git/devbot:git-commits/SKILL.md" ]
}

@test "_link_skill_farm leaves a module-authored link that points outside the farm" {
  # `.opencode/skills/signoz` is wired by the signoz module itself, to its
  # generated skills under storage/. The farm reconcile owns only links into
  # <devbot_dir>/skills, so it must not remove this one.
  mkdir -p "${PROJECT}/.agents/skills/devbot"
  mkdir -p "${PROJECT}/.opencode/skills"
  ln -sfn "${DEV_BOT_ROOT}/storage/signoz/skills" "${PROJECT}/.opencode/skills/signoz"

  run bash -c '
    set -euo pipefail
    _ok() { :; }; _warn() { :; }; _skip() { :; }
    _devbot_get_project_dir() { printf ".agents"; }
    OPENCODE_DIR="${1}/.opencode"
    # The function under test calls _devbot_list_has; eval the real one so its
    # membership branch runs instead of dying on an undefined command (which,
    # under `set -e` with an `if`, silently takes the other branch).
    eval "$(sed -n "\|^_devbot_list_has() {\$|,\|^}\$|p" "${3}/src/_shared/functions.sh")"
    eval "$(sed -n "\|^_link_skill_farm() {\$|,\|^}\$|p" "${2}")"
    _link_skill_farm "${1}"
  ' _ "${PROJECT}" "${MODULE_DIR}/init.sh" "${DEV_BOT_ROOT}"
  assert_success

  assert [ -L "${PROJECT}/.opencode/skills/signoz" ]
  # Prove the membership helper really was sourced above: without it the prune
  # branch is dead and this test would pass for the wrong reason.
  run bash -c '
    eval "$(sed -n "\|^_devbot_list_has() {\$|,\|^}\$|p" "${1}/src/_shared/functions.sh")"
    type _devbot_list_has >/dev/null
  ' _ "${DEV_BOT_ROOT}"
  assert_success
}

@test "init prunes a farm link whose entry disappeared" {
  # The seed has two entries; init links both, then the test drops one and
  # re-runs. This tree is the scenario's only reader, so it is mutated in place.
  scenario farm-prune
  assert [ -L "${PROJECT}/.opencode/skills/gone" ]

  rm -r -f "${PROJECT}/.agents/skills/gone"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ ! -e "${PROJECT}/.opencode/skills/gone" ]
}


@test "init keeps a farm entry whose target lives under dev-bot (external modules)" {
  # External-module skills enter the farm as links into the vendored source
  # (vendor/<vendor>/<repo>/skills), so their .opencode/skills link RESOLVES under
  # DEV_BOT_ROOT. The handover sweep and the declared-asset pruner both treat a
  # link resolving under dev-bot as a stale asset, which deleted every external
  # module skill on each reinit.
  scenario farm-external

  # The second run is the assertion: a reinit must keep the link.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/skills/probe-external" ]
  # And the skill behind it is reachable: the id is the SKILL.md parent directory.
  assert [ -f "${PROJECT}/.opencode/skills/probe-external/git-commits/SKILL.md" ]
}


# ── An ancestor project's skill farm is registered too (audit-01 FAIL-1) ──────
# V2 rescans every ancestor's `.opencode/skills`, so a dev-bot project nested
# inside another registers the ancestor's catalogue beside its own. init cannot
# remove those entries — they live in the ancestor's tree — but it must say so:
# the 101 duplicated skills and the 63 from disabled modules were invisible.

@test "init warns when an ancestor project supplies its own skill farm" {
  local parent="${BATS_TEST_TMPDIR}/ancestor" child="${BATS_TEST_TMPDIR}/ancestor/nested"
  mkdir -p "${parent}/.opencode/skills/devbot/probe-skill" "${child}"
  printf -- '---\nname: probe-skill\n---\n' \
    >"${parent}/.opencode/skills/devbot/probe-skill/SKILL.md"
  printf '{ "harness": "opencode-v2" }\n' >"${child}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${child}"

  assert_success
  assert_output --partial "an ancestor project supplies its own skill farm"
  assert_output --partial "${parent}"
  # The count is the point: one skill on each side is not a problem, a whole
  # catalogue is.
  assert_output --partial "1 skill(s)"
}

@test "init does not warn about an ancestor skill farm when there is none" {
  # The warm scenario's ancestors (mktemp dirs up to /) seed no farm.
  init_said default
  refute_output --partial "an ancestor project supplies its own skill farm"
}

@test "init finds an ancestor farm under that project's own devbot_dir" {
  # An ancestor that renamed its vault keeps its farm at <devbot_dir>/skills.
  # A hard-coded .agents missed it, so this warning never fired for it.
  local parent="${BATS_TEST_TMPDIR}/vault-ancestor" child="${BATS_TEST_TMPDIR}/vault-ancestor/nested"
  mkdir -p "${parent}/.vault/skills/devbot/probe-skill" "${child}"
  printf -- '---\nname: probe-skill\n---\n' \
    >"${parent}/.vault/skills/devbot/probe-skill/SKILL.md"
  printf '{ "harness": "opencode-v2", "devbot_dir": ".vault" }\n' >"${parent}/.devbot.project.jsonc"
  printf '{ "harness": "opencode-v2" }\n' >"${child}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${child}"

  assert_success
  assert_output --partial "${parent}"
  assert_output --partial "1 skill(s)"
}
