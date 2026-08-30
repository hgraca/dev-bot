#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/install_tests.bats
# Tests for src/agentic/github/install.sh — pins that the idempotency guard
# short-circuits to skip when gh is already present, so the real
# sudo/apt/dnf/brew install path is never reached on re-installs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/src/agentic/github/install.sh"
}

@test "install.sh: skips install when gh is already present" {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  cat > "${MOCKBIN}/gh" <<'MOCK'
#!/usr/bin/env bash
echo "gh version 2.45.0 (2024-05-06)"
MOCK
  chmod +x "${MOCKBIN}/gh"
  export PATH="${MOCKBIN}:${PATH}"

  run bash "${INSTALL_SH}"

  assert_success
  # Skip path taken — no "Installing gh via ..." install branch reached.
  [[ "$output" == *"gh (gh version"* ]]
  [[ "$output" != *"Installing gh via"* ]]
}
