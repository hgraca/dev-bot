#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/versions_env_tests.bats
# Module pins are machine-local state: versions.env.dist is the shipped default.
#
# `devbot update` bumps a module's pin in place. While the pin was tracked, that
# bump left the release checkout dirty — the next update stashed the dirt and
# popped it back, so the tree never came clean and the stash round-trip became
# the collision point between a machine's pins and the release's.
#
# Rules under test:
#   * the shipped default is the committed versions.env.dist,
#   * reading prefers the live copy and falls back to the default,
#   * reading never creates the live copy — a seeded stale copy would shadow
#     every later release bump for a module that has no writer,
#   * only a writer seeds, and seeding is atomic (no half-written pin),
#   * a module with neither file is silent, not fatal, under `set -euo pipefail`.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  FUNCTIONS="${PROJECT_ROOT}/src/_shared/functions.sh"
  MODULE="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${MODULE}"
}

# Run a snippet in a fresh, EMPTY shell with the shared library loaded — `env -i`
# so nothing leaks in from the developer's own profile.
_shared_shell() {
  run env -i PATH="${PATH}" bash -c "set -euo pipefail; source '${FUNCTIONS}'; ${SNIPPET}"
}

@test "reads the live pin when the machine has one" {
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"
  printf 'PIN=9.9.9\n' >"${MODULE}/versions.env"

  SNIPPET="_devbot_versions_env '${MODULE}'"
  _shared_shell
  assert_output "${MODULE}/versions.env"
}

@test "falls back to the shipped default when there is no live pin" {
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"

  SNIPPET="_devbot_versions_env '${MODULE}'"
  _shared_shell
  assert_output "${MODULE}/versions.env.dist"
}

@test "reading never creates the live pin" {
  # A module with no writer must keep following its shipped default: a seeded
  # stale copy would shadow every later release bump forever.
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"

  SNIPPET="_devbot_versions_env '${MODULE}' >/dev/null; printf 'read-ok'"
  _shared_shell
  assert_output "read-ok"
  [ ! -e "${MODULE}/versions.env" ]
}

@test "sources the live pin when present, the default otherwise" {
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"
  SNIPPET="_devbot_versions_env_source '${MODULE}'; echo \${PIN}"
  _shared_shell
  assert_output "1.2.3"

  printf 'PIN=9.9.9\n' >"${MODULE}/versions.env"
  SNIPPET="_devbot_versions_env_source '${MODULE}'; echo \${PIN}"
  _shared_shell
  assert_output "9.9.9"
}

@test "seeding creates the live pin from the default, leaving no temp file" {
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"

  SNIPPET="_devbot_versions_env_seed '${MODULE}' && echo seeded"
  _shared_shell
  assert_output "seeded"
  grep -qxF 'PIN=1.2.3' "${MODULE}/versions.env"
  [ ! -e "${MODULE}/versions.env.tmp" ]
}

@test "seeding never touches an existing live pin" {
  printf 'PIN=1.2.3\n' >"${MODULE}/versions.env.dist"
  printf 'PIN=9.9.9\n' >"${MODULE}/versions.env"

  SNIPPET="_devbot_versions_env_seed '${MODULE}' && echo seeded"
  _shared_shell
  assert_output "seeded"
  grep -qxF 'PIN=9.9.9' "${MODULE}/versions.env"
}

@test "seeding fails loudly when the module ships no default" {
  SNIPPET="_devbot_versions_env_seed '${MODULE}'"
  _shared_shell
  assert_failure
  [ ! -e "${MODULE}/versions.env" ]
}

@test "a module with neither file is silent, not fatal" {
  SNIPPET="_devbot_versions_env '${MODULE}'"
  _shared_shell
  assert_success
  assert_output ""

  SNIPPET="_devbot_versions_env_source '${MODULE}'; printf 'ok'"
  _shared_shell
  assert_success
  assert_output "ok"
}

# ── the repo-wide contract ────────────────────────────────────────────────────

# Every tracked shipped pin, one per line.
_shipped_pins() {
  git ls-files '*versions.env.dist'
}

@test "no module pin is tracked: every shipped pin is a .dist" {
  cd "${PROJECT_ROOT}"
  run git ls-files '*versions.env'
  assert_success
  assert_output ""

  local dist files=0
  while IFS= read -r dist; do
    files=$((files + 1))
    [ -f "${dist}" ] || fail "missing shipped pin default: ${dist}"
  done < <(_shipped_pins)
  [ "${files}" -ge 5 ] || fail "expected at least five shipped pins, found ${files}"
}

@test "every shipped pin goes through the shared reader" {
  # Runtime files only — a module's tests, fixtures and docs may name the helper
  # without applying the pin, and `functions.sh` is sourced, so executable
  # permission is not the discriminator. Comments are stripped before matching
  # and the call must start a line or a command substitution, so prose cannot
  # stand in for one and a *writer* (`_devbot_versions_env_seed`) cannot either.
  cd "${PROJECT_ROOT}"
  local dist module_dir files=0
  local call='(^[[:space:]]*|\$\()[[:space:]]*_devbot_versions_env(_source)?[[:space:]]'
  while IFS= read -r dist; do
    module_dir="$(dirname "${dist}")"
    run bash -c '
      grep -rhE . "${2%/}" \
        --include="*.sh" --include="*.bash" --include="*.py" --include="*.ts" \
        --exclude-dir=tests 2>/dev/null \
      | sed -E "s/#.*\$//" \
      | grep -qE "$1"
    ' _ "${call}" "${module_dir}"
    [ "${status}" -eq 0 ] \
      || fail "${module_dir} never calls a shared pin reader for ${dist}"
    files=$((files + 1))
  done < <(_shipped_pins)
  [ "${files}" -ge 5 ] || fail "expected at least five shipped pins, found ${files}"
}

@test "the live pin is gitignored so an update bump never dirties the tree" {
  cd "${PROJECT_ROOT}"
  run git check-ignore --no-index -q "src/agentic/playwright/versions.env"
  assert_success
  run git check-ignore --no-index -q "src/agentic/playwright/versions.env.tmp"
  assert_success
  run git check-ignore --no-index -q "src/harnesses/opencode/versions.env"
  assert_success
}
