#!/usr/bin/env bats
# =============================================================================
# src/agentic/tree/tests/install_tests.bats
# Tests for src/agentic/tree/install.sh — pins that the idempotency guard
# short-circuits to skip when tree is already present, so the real
# sudo/apt/dnf/brew install path is never reached on re-installs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/src/agentic/tree/install.sh"
}

@test "install.sh: skips install when tree is already present" {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  cat > "${MOCKBIN}/tree" <<'MOCK'
#!/usr/bin/env bash
echo "tree v2.1.1"
MOCK
  chmod +x "${MOCKBIN}/tree"
  # Only mockbin + a dir with nothing harmful: tree must resolve from mockbin,
  # and uname must resolve from the real PATH for the skip branch (which never
  # reaches uname). Prepend mockbin to the real PATH.
  export PATH="${MOCKBIN}:${PATH}"

  run bash "${INSTALL_SH}"

  assert_success
  # Skip path taken — no "Installing tree via ..." install branch reached.
  [[ "$output" == *"tree (tree"* ]]
  [[ "$output" != *"Installing tree via"* ]]
}
