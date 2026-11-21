#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/git_exclude_path_tests.bats
# The repo-local exclude file must be resolved through git, so a module writing
# it from a linked worktree (where `.git` is a file) reaches the shared
# `.git/info/exclude` instead of failing on `mkdir .git/info`.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SANDBOX="$(mktemp -d)"
  REPO="${SANDBOX}/repo"

  # shellcheck source=/dev/null
  source "${MODULE_DIR}/functions.sh"
}

teardown() {
  rm -rf "${SANDBOX}"
}

_git() {
  local dir="$1"
  shift
  git -C "${dir}" -c user.email=test@example.com -c user.name=test "$@"
}

_make_repo() {
  _git "${SANDBOX}" init -q repo
  _git "${REPO}" commit -q --allow-empty -m init
}

@test "resolves info/exclude in a plain checkout" {
  _make_repo

  run _devbot_git_exclude_path "${REPO}"

  assert_success
  assert_equal "$(cd "${REPO}" && pwd)/.git/info/exclude" "${output}"
}

@test "resolves the shared info/exclude from a linked worktree" {
  _make_repo
  _git "${REPO}" worktree add -q "${SANDBOX}/wt" -b side

  run _devbot_git_exclude_path "${SANDBOX}/wt"

  assert_success
  assert_equal "$(cd "${REPO}" && pwd)/.git/info/exclude" "${output}"
}

@test "falls back to the literal path outside a git repository" {
  mkdir -p "${SANDBOX}/plain"

  run _devbot_git_exclude_path "${SANDBOX}/plain"

  assert_success
  assert_equal "${SANDBOX}/plain/.git/info/exclude" "${output}"
}

@test "a directory nested in a repository resolves to the enclosing exclude" {
  # Writing <nested>/.git/info would fabricate a gitdir git then treats as a
  # broken repo; the file git reads is the enclosing repository's exclude.
  _make_repo
  mkdir -p "${REPO}/nested"

  run _devbot_git_exclude_path "${REPO}/nested"

  assert_success
  assert_equal "$(cd "${REPO}" && pwd)/.git/info/exclude" "${output}"
}

@test "a worktree upsert reaches the shared exclude instead of failing" {
  _make_repo
  _git "${REPO}" worktree add -q "${SANDBOX}/wt" -b side

  exclude="$(_devbot_git_exclude_path "${SANDBOX}/wt")"
  run _upsert_gitignore_section "${exclude}" "# >>> PROBE" "# <<< PROBE" "/probe"

  assert_success
  assert [ -f "${exclude}" ]
  grep -qx "/probe" "${exclude}"
}
