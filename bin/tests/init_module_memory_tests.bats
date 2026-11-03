#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_module_memory_tests.bats
#
# `<devbot_dir>/memory/active/modules/` holds generated module memory: each
# enabled module writes its own file there on init, and reinit clears the folder
# first. The content is machine-local output, so init must keep it out of the
# project's history — otherwise every reinit shows up as a diff in every repo.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  PROJECT="$(mktemp -d)"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  # Production init.sh, trailing `main "$@"` stripped so sourcing it is inert.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX}/bin/init.sh"

  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_ok()   { true; }
_warn() { echo "WARN: $*"; }
STUB
  {
    awk '/^_upsert_section_impl\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_upsert_gitignore_section\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_is_plain_relative_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  export DEV_BOT_ROOT="${SANDBOX}"
  git -C "${PROJECT}" init -q
}

teardown() {
  rm -rf "${SANDBOX}" "${PROJECT}" 2>/dev/null || true
}

# Source the production helpers without running main.
load_init() {
  # shellcheck source=/dev/null
  source "${SANDBOX}/bin/init.sh"
}

@test "adds the module memory folder to .gitignore" {
  load_init

  _ignore_module_memory "${PROJECT}" ".agents"

  run cat "${PROJECT}/.gitignore"
  assert_output --partial "# >>> DEVBOT - module memory"
  assert_output --partial ".agents/memory/active/modules/"
}

@test "is idempotent across repeated inits" {
  load_init

  _ignore_module_memory "${PROJECT}" ".agents"
  _ignore_module_memory "${PROJECT}" ".agents"
  _ignore_module_memory "${PROJECT}" ".agents"

  run grep -c "DEVBOT - module memory" "${PROJECT}/.gitignore"
  assert_output "2"
  run grep -cF ".agents/memory/active/modules/" "${PROJECT}/.gitignore"
  assert_output "1"
}

@test "adds the rule in a linked worktree, where .git is a file" {
  local base
  base="$(mktemp -d)"
  git -C "${base}" init -q
  git -C "${base}" config user.email t@example.com
  git -C "${base}" config user.name t
  printf 'x\n' > "${base}/f"
  git -C "${base}" add f
  git -C "${base}" commit -qm init
  rm -rf "${PROJECT}"
  git -C "${base}" worktree add -q "${PROJECT}" -b wt 2>/dev/null
  assert [ -f "${PROJECT}/.git" ]

  load_init
  _ignore_module_memory "${PROJECT}" ".agents"

  run cat "${PROJECT}/.gitignore"
  assert_output --partial ".agents/memory/active/modules/"
  rm -rf "${base}"
}

@test "preserves the .gitignore mode" {
  printf 'node_modules/\n' > "${PROJECT}/.gitignore"
  chmod 644 "${PROJECT}/.gitignore"

  load_init
  _ignore_module_memory "${PROJECT}" ".agents"

  local mode
  mode="$(stat -c %a "${PROJECT}/.gitignore" 2>/dev/null || stat -f %Lp "${PROJECT}/.gitignore")"
  assert_equal "${mode}" "644"
}

@test "the ignore rule is written before the first module init runs" {
  # main is linear, so call order is the invariant: the rule must exist before
  # any module writes into the folder it protects.
  local rule module
  rule="$(grep -n '_ignore_module_memory "${PROJECT_DIR}"' "${PROJECT_ROOT}/bin/init.sh" | head -1 | cut -d: -f1)"
  module="$(grep -n '_init_modules "${DEV_BOT_ROOT}/src/tools"' "${PROJECT_ROOT}/bin/init.sh" | head -1 | cut -d: -f1)"

  assert [ -n "${rule}" ]
  assert [ -n "${module}" ]
  assert [ "${rule}" -lt "${module}" ]
}

@test "keeps the project's existing ignore rules" {
  printf 'node_modules/\n' > "${PROJECT}/.gitignore"
  load_init

  _ignore_module_memory "${PROJECT}" ".agents"

  run cat "${PROJECT}/.gitignore"
  assert_output --partial "node_modules/"
  assert_output --partial ".agents/memory/active/modules/"
}

@test "honours a custom devbot dir" {
  load_init

  _ignore_module_memory "${PROJECT}" ".ai/devbot"

  run cat "${PROJECT}/.gitignore"
  assert_output --partial ".ai/devbot/memory/active/modules/"
}

@test "writes no rule for a devbot_dir that escapes the project" {
  load_init

  _ignore_module_memory "${PROJECT}" "../elsewhere"

  refute [ -e "${PROJECT}/.gitignore" ]
}

@test "writes no rule for an absolute devbot_dir" {
  load_init

  _ignore_module_memory "${PROJECT}" "/etc"

  refute [ -e "${PROJECT}/.gitignore" ]
}

@test "writes no wildcard rule for a devbot_dir with glob metacharacters" {
  load_init

  _ignore_module_memory "${PROJECT}" "*"

  refute [ -e "${PROJECT}/.gitignore" ]
}

@test "does nothing outside a git repository" {
  local plain
  plain="$(mktemp -d)"

  load_init
  _ignore_module_memory "${plain}" ".agents"

  refute [ -e "${plain}/.gitignore" ]
  rm -rf "${plain}"
}

@test "the ignored folder is actually ignored by git" {
  load_init
  _ignore_module_memory "${PROJECT}" ".agents"

  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# generated\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"

  run git -C "${PROJECT}" status --porcelain -- .agents
  assert_output ""
}
