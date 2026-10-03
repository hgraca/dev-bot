#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/codebase_memory_root_tests.bats
# _devbot_codebase_memory_root — the repo root the shared codebase-memory
# gateway bind-mounts read-only. A gateway rooted at a fixed $HOME cannot see a
# registered project that lives outside it, so bin/up.sh exports this derived
# value before compose interpolates it (audit-69 NOTE-1 / audit-70 FAIL).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  CONF_DIR="${SANDBOX}/conf"
  mkdir -p "${CONF_DIR}"
}

teardown() {
  [[ -n "${SANDBOX:-}" ]] && rm -rf "${SANDBOX}"
}

# _root <home> <projects-json>
# Writes a sandbox global config registering <projects-json> and prints the
# helper's output for the given HOME. CODEBASE_MEMORY_ROOT stays unset.
_root() {
  local home="$1" projects="$2"
  printf '{ "projects": %s }\n' "${projects}" > "${CONF_DIR}/.devbot.global.jsonc"
  run env -u CODEBASE_MEMORY_ROOT DEV_BOT_ROOT="${CONF_DIR}" HOME="${home}" \
    bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_codebase_memory_root"
}

@test "defaults to \$HOME when no projects are registered" {
  _root "${SANDBOX}/home" '[]'
  assert_success
  assert_output "${SANDBOX}/home"
}

@test "stays \$HOME when every project sits under it" {
  mkdir -p "${SANDBOX}/home/p1" "${SANDBOX}/home/p2"
  _root "${SANDBOX}/home" "[\"${SANDBOX}/home/p1\", \"${SANDBOX}/home/p2\"]"
  assert_success
  assert_output "${SANDBOX}/home"
}

@test "widens to the shared ancestor of \$HOME and an outside project" {
  mkdir -p "${SANDBOX}/home" "${SANDBOX}/other/p"
  _root "${SANDBOX}/home" "[\"${SANDBOX}/other/p\"]"
  assert_success
  assert_output "${SANDBOX}"
}

@test "never resolves to / — stays \$HOME when the ancestor is the root" {
  _root "/usr" "[\"/etc\"]"
  assert_success
  assert_output "/usr"
}

@test "an explicit CODEBASE_MEMORY_ROOT wins" {
  printf '{ "projects": [] }\n' > "${CONF_DIR}/.devbot.global.jsonc"
  run env DEV_BOT_ROOT="${CONF_DIR}" HOME="${SANDBOX}/home" \
    CODEBASE_MEMORY_ROOT="${SANDBOX}/explicit" \
    bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_codebase_memory_root"
  assert_success
  assert_output "${SANDBOX}/explicit"
}

# ── Persisted root (audit-80 FAIL-3) ─────────────────────────────────────────
# The gateway root is machine-global, but the derived value depends on the
# caller's env; an env-less later invocation (the harness-launch `devbot`)
# reverted the mount. A persisted config key pins it.

@test "a persisted codebase_memory_root config value is used when the env is unset" {
  printf '{ "projects": [], "codebase_memory_root": "%s" }\n' "${SANDBOX}/persisted" \
    > "${CONF_DIR}/.devbot.global.jsonc"
  run env -u CODEBASE_MEMORY_ROOT DEV_BOT_ROOT="${CONF_DIR}" HOME="${SANDBOX}/home" \
    bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_codebase_memory_root"
  assert_success
  assert_output "${SANDBOX}/persisted"
}

@test "an explicit CODEBASE_MEMORY_ROOT still wins over the persisted config root" {
  printf '{ "projects": [], "codebase_memory_root": "%s" }\n' "${SANDBOX}/persisted" \
    > "${CONF_DIR}/.devbot.global.jsonc"
  run env DEV_BOT_ROOT="${CONF_DIR}" HOME="${SANDBOX}/home" \
    CODEBASE_MEMORY_ROOT="${SANDBOX}/explicit" \
    bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_codebase_memory_root"
  assert_success
  assert_output "${SANDBOX}/explicit"
}

@test "persist writes the config root and preserves JSONC comments" {
  cat > "${CONF_DIR}/.devbot.global.jsonc" <<'EOF'
{
  // keep me
  "projects": []
}
EOF
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    DEV_BOT_ROOT='${CONF_DIR}' _devbot_persist_codebase_memory_root '${SANDBOX}/persisted'
  "
  assert_success

  run grep -q '// keep me' "${CONF_DIR}/.devbot.global.jsonc"
  assert_success

  run env -u CODEBASE_MEMORY_ROOT DEV_BOT_ROOT="${CONF_DIR}" HOME="${SANDBOX}/home" \
    bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_codebase_memory_root"
  assert_success
  assert_output "${SANDBOX}/persisted"
}

@test "persist ignores a root that is / or relative" {
  printf '{ "projects": [] }\n' > "${CONF_DIR}/.devbot.global.jsonc"
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    DEV_BOT_ROOT='${CONF_DIR}' _devbot_persist_codebase_memory_root '/'
    DEV_BOT_ROOT='${CONF_DIR}' _devbot_persist_codebase_memory_root 'relative/path'
  "
  assert_success
  # Neither invalid root may be written to the config.
  run grep -q 'codebase_memory_root' "${CONF_DIR}/.devbot.global.jsonc"
  assert_failure
}

@test "ignores registered project paths that do not exist" {
  mkdir -p "${SANDBOX}/home/p"
  _root "${SANDBOX}/home" "[\"${SANDBOX}/missing\", \"${SANDBOX}/home/p\"]"
  assert_success
  assert_output "${SANDBOX}/home"
}

# ── Scope warning (audit-77 FAIL-1 / audit-78 FAIL-3) ────────────────────────

@test "warns when a project sits outside the gateway root" {
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_warn_codebase_memory_scope /app /home/ubuntu
  "
  assert_success
  assert_output --partial 'outside the gateway repo root'
  assert_output --partial '/app'
}

@test "stays silent when the project is at or under the gateway root" {
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_warn_codebase_memory_scope /home/ubuntu /home/ubuntu
    _devbot_warn_codebase_memory_scope /home/ubuntu/proj /home/ubuntu
  "
  assert_success
  refute_output --partial 'outside'
}
