#!/usr/bin/env bats
# =============================================================================
# bin/tests/docs_install_url_tests.bats
# Tests for the docs-site install command invariant.
#
# The install command must be served from the GitHub Pages site
# (https://get-e.github.io/dev-bot/install.sh) because the repo is private and
# raw.githubusercontent.com only serves public repos. Validates that:
#   - install.sh and the docs reference the Pages-hosted install script
#   - the Pages workflow stages install.sh into the built site
#   - raw.githubusercontent.com remains only in the hgraca fork test fixture
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_CMD='curl -fsSL https://get-e.github.io/dev-bot/install.sh | bash -s -- --ssh'
}

@test "install.sh header documents the Pages-hosted install command" {
  run grep -F "${INSTALL_CMD}" "${PROJECT_ROOT}/install.sh"
  assert_success
}

@test "docs hero install command uses the Pages URL in index.md and cli-commands.md" {
  for f in "${PROJECT_ROOT}/docs/index.md" "${PROJECT_ROOT}/docs/cli-commands.md"; do
    run grep -F "${INSTALL_CMD}" "$f"
    assert_success
  done
}

@test "docs JS rebuilds the install command from the Pages URL" {
  run grep -F "'curl -fsSL https://' + org + '.github.io/' + repo + '/install.sh | bash -s -- --ssh'" "${PROJECT_ROOT}/docs/_layouts/default.html"
  assert_success
}

@test "no tracked docs or install.sh file references raw.githubusercontent.com" {
  run git -C "${PROJECT_ROOT}" grep -n "raw.githubusercontent.com" -- install.sh docs
  assert_failure
}

@test "hgraca fork test fixture keeps its own public raw URL" {
  run git -C "${PROJECT_ROOT}" grep -n "raw.githubusercontent.com" -- tests/test-project/test-reinit.sh
  assert_success
}

@test "workflow stages install.sh into the Pages build" {
  run grep -F "cp ../install.sh _site/install.sh" "${PROJECT_ROOT}/.github/workflows/jekyll-gh-pages.yml"
  assert_success
}
