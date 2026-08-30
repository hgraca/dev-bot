#!/usr/bin/env bats
# =============================================================================
# bin/tests/install_bootstrap_tests.bats
# Tests for the root install.sh direct-install bootstrap.
#
# Validates that:
#   - --help and unknown-option handling behave
#   - the clone URL is built from --org/--repo/--host pieces, with
#     DEV_BOT_* env vars overriding literals and flags overriding env
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/install.sh"
}

@test "install.sh --help exits 0 and shows usage" {
  run bash "${INSTALL_SH}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install.sh"* ]]
}

@test "install.sh rejects unknown options" {
  run bash "${INSTALL_SH}" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "install.sh --print-url uses canonical defaults" {
  run env -u DEV_BOT_ORG -u DEV_BOT_REPO -u DEV_BOT_HOST bash "${INSTALL_SH}" --print-url
  [ "$status" -eq 0 ]
  [ "$output" == "https://github.com/GET-E/dev-bot.git" ]
}

@test "install.sh --print-url honors --org/--repo/--host" {
  run bash "${INSTALL_SH}" --print-url --org other-org --repo other-repo --host git.example.com
  [ "$status" -eq 0 ]
  [ "$output" == "https://git.example.com/other-org/other-repo.git" ]
}

@test "install.sh --print-url honors DEV_BOT_* env vars" {
  run env DEV_BOT_ORG=env-org DEV_BOT_REPO=env-repo bash "${INSTALL_SH}" --print-url
  [ "$status" -eq 0 ]
  [ "$output" == "https://github.com/env-org/env-repo.git" ]
}

@test "install.sh flags override DEV_BOT_* env vars" {
  run env DEV_BOT_ORG=env-org bash "${INSTALL_SH}" --print-url --org flag-org
  [ "$status" -eq 0 ]
  [ "$output" == "https://github.com/flag-org/dev-bot.git" ]
}

# ── Standalone ref-resolution tests ──────────────────────────────────────────
# These exercise the standalone path (clone / pull). install.sh skips it when
# run from inside a clone (PWD/bin/install.sh exists), so we copy install.sh
# into a sandbox, cd there, and mock `curl` (GitHub API) + `git` on PATH.

_setup_standalone_sandbox() {
  SANDBOX_DIR="$(mktemp -d)"
  export HOME="${SANDBOX_DIR}/home"
  mkdir -p "${HOME}"
  cp "${INSTALL_SH}" "${SANDBOX_DIR}/install.sh"

  MOCKBIN="${SANDBOX_DIR}/mockbin"
  mkdir -p "${MOCKBIN}"
  export GIT_ARGS_FILE="${SANDBOX_DIR}/git.args"
  export CURL_ARGS_FILE="${SANDBOX_DIR}/curl.args"
  : > "${GIT_ARGS_FILE}"
  : > "${CURL_ARGS_FILE}"
  export PATH="${MOCKBIN}:${PATH}"
}

_mock_git() {
  cat > "${MOCKBIN}/git" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${GIT_ARGS_FILE}"
if [[ "$1" == "clone" ]]; then
  # git clone ... <url> <dir> — create minimal install tree so the
  # in-repo installer + CLI link steps have something to run.
  dir="${!#}"
  mkdir -p "${dir}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${dir}/bin/install.sh"
  : > "${dir}/bin/devbot"
fi
MOCK
  chmod +x "${MOCKBIN}/git"
}

# API returns a release tag
_mock_curl_with_tag() {
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CURL_ARGS_FILE}"
echo '{"tag_name": "v1.2.3"}'
MOCK
  chmod +x "${MOCKBIN}/curl"
}

# API 404s (no releases yet)
_mock_curl_no_releases() {
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CURL_ARGS_FILE}"
echo '{"message": "Not Found"}' >&2
exit 22
MOCK
  chmod +x "${MOCKBIN}/curl"
}

@test "install.sh standalone clones the latest release tag when no branch given" {
  _setup_standalone_sandbox
  _mock_git
  _mock_curl_with_tag
  cd "${SANDBOX_DIR}"

  run bash "${SANDBOX_DIR}/install.sh" --install-dir "${SANDBOX_DIR}/install"

  assert_success
  run cat "${GIT_ARGS_FILE}"
  assert_output --regexp 'clone --depth 1 --branch v1\.2\.3'
}

@test "install.sh standalone falls back to main when no release tag exists" {
  _setup_standalone_sandbox
  _mock_git
  _mock_curl_no_releases
  cd "${SANDBOX_DIR}"

  run bash "${SANDBOX_DIR}/install.sh" --install-dir "${SANDBOX_DIR}/install"

  assert_success
  INSTALL_OUTPUT="$output"
  run cat "${GIT_ARGS_FILE}"
  assert_output --regexp 'clone --depth 1 --branch main'
  [[ "$INSTALL_OUTPUT" == *"no release tag"* ]]
}

@test "install.sh standalone honors explicit --branch over release tag" {
  _setup_standalone_sandbox
  _mock_git
  _mock_curl_with_tag
  cd "${SANDBOX_DIR}"

  run bash "${SANDBOX_DIR}/install.sh" --install-dir "${SANDBOX_DIR}/install" --branch dev8

  assert_success
  run cat "${GIT_ARGS_FILE}"
  assert_output --regexp 'clone --depth 1 --branch dev8'
  # curl must never be consulted when a branch is explicit
  [ ! -s "${CURL_ARGS_FILE}" ]
}

@test "install.sh standalone updates an existing clone to the latest release tag" {
  _setup_standalone_sandbox
  _mock_git
  _mock_curl_with_tag
  INSTALL_DIR="${SANDBOX_DIR}/install"
  mkdir -p "${INSTALL_DIR}/.git" "${INSTALL_DIR}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${INSTALL_DIR}/bin/install.sh"
  : > "${INSTALL_DIR}/bin/devbot"
  cd "${SANDBOX_DIR}"

  run bash "${SANDBOX_DIR}/install.sh" --install-dir "${INSTALL_DIR}"

  assert_success
  run cat "${GIT_ARGS_FILE}"
  assert_output --regexp 'fetch origin tag v1\.2\.3'
  assert_output --regexp 'checkout v1\.2\.3'
}

@test "install.sh standalone pulls explicit branch on existing clone" {
  _setup_standalone_sandbox
  _mock_git
  _mock_curl_with_tag
  INSTALL_DIR="${SANDBOX_DIR}/install"
  mkdir -p "${INSTALL_DIR}/.git" "${INSTALL_DIR}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${INSTALL_DIR}/bin/install.sh"
  : > "${INSTALL_DIR}/bin/devbot"
  cd "${SANDBOX_DIR}"

  run bash "${SANDBOX_DIR}/install.sh" --install-dir "${INSTALL_DIR}" --branch dev8

  assert_success
  run cat "${GIT_ARGS_FILE}"
  assert_output --regexp 'pull --ff-only origin dev8'
}
