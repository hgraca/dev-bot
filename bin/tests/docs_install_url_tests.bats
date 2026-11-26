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
#   - the workflow refuses a publishing source that ignores its artifact
#   - raw.githubusercontent.com remains only in the hgraca fork test fixture
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_CMD='curl -fsSL https://get-e.github.io/dev-bot/install.sh | bash -s -- --ssh'
  BUILD_TYPE_SH="${PROJECT_ROOT}/src/agentic/docs/tools/assert-pages-build-type.sh"
}

# The guard reads the Pages settings through `gh`; stub it to a fixed answer
# and record the arguments, so the repo it asks about is verifiable.
stub_gh() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_GH_ARGS:?}"
if [[ "${STUB_GH_STATUS:-0}" != "0" ]]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit "${STUB_GH_STATUS}"
fi
printf '%s\n' "${STUB_BUILD_TYPE-}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "install.sh header documents the Pages-hosted install command" {
  run grep -F "${INSTALL_CMD}" "${PROJECT_ROOT}/install.sh"
  assert_success
}

@test "docs hero install command uses the Pages URL in index.md and the CLI module page" {
  for f in "${PROJECT_ROOT}/docs/index.md" "${PROJECT_ROOT}/src/tools/devbot-cli/docs.md"; do
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

@test "workflow runs the Pages build-type guard for this repository" {
  run grep -F 'src/agentic/docs/tools/assert-pages-build-type.sh "${{ github.repository }}"' \
    "${PROJECT_ROOT}/.github/workflows/jekyll-gh-pages.yml"
  assert_success
}

@test "guard fails when Pages serves a branch instead of the artifact" {
  stub_gh
  STUB_GH_ARGS="${BATS_TEST_TMPDIR}/gh-args" STUB_BUILD_TYPE=legacy \
    run bash "${BUILD_TYPE_SH}" acme/example
  assert_failure
  assert_output --partial "build_type=legacy"
  assert_output --partial "generated pages and install.sh 404"
  assert_output --partial "gh api -X PUT repos/acme/example/pages -f build_type=workflow"
  run grep -F "repos/acme/example/pages" "${BATS_TEST_TMPDIR}/gh-args"
  assert_success
}

@test "guard passes when Pages publishes the artifact" {
  stub_gh
  STUB_GH_ARGS="${BATS_TEST_TMPDIR}/gh-args" STUB_BUILD_TYPE=workflow \
    run bash "${BUILD_TYPE_SH}" acme/example
  assert_success
  assert_output --partial "build_type=workflow"
  run grep -F "repos/acme/example/pages" "${BATS_TEST_TMPDIR}/gh-args"
  assert_success
}

@test "guard fails loudly when the Pages settings cannot be read" {
  stub_gh
  STUB_GH_ARGS="${BATS_TEST_TMPDIR}/gh-args" STUB_GH_STATUS=1 \
    run bash "${BUILD_TYPE_SH}" acme/example
  assert_failure
  assert_output --partial "FATAL: cannot read the Pages settings for acme/example"
  assert_output --partial "HTTP 404"
}

@test "guard refuses an unknown build_type without calling it a branch source" {
  stub_gh
  STUB_GH_ARGS="${BATS_TEST_TMPDIR}/gh-args" STUB_BUILD_TYPE= \
    run bash "${BUILD_TYPE_SH}" acme/example
  assert_failure
  assert_output --partial "cannot"
  assert_output --partial "Set the Pages source to"
  refute_output --partial "serves branch docs/"
}
