#!/usr/bin/env bats
# =============================================================================
# src/agentic/format-yml/tests/install_tests.bats
# Tests for src/agentic/format-yml/install.sh — verifies the prettier guard
# takes the skip path when prettier is present and the install path (via npm)
# when it is missing, without any real npm side effects.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/src/agentic/format-yml/install.sh"
}

_setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  export NPM_ARGS_FILE="${SANDBOX}/npm.args"
  : > "${NPM_ARGS_FILE}"
  # Build a PATH with only the dirs that hold python3/node/npm plus mockbin —
  # deliberately excluding any dir that also holds prettier, so the test can
  # control whether `command -v prettier` succeeds. Cross-platform safe.
  local dirs=""
  local bin d
  for bin in python3 node npm; do
    d="$(dirname "$(command -v "$bin")")"
    case ":$dirs:" in
      *":$d:"*) ;;
      *) dirs="${dirs}:${d}" ;;
    esac
  done
  export PATH="${MOCKBIN}:${dirs#:}"
}

# Mock npm that records its invocation instead of installing anything.
_mock_npm() {
  cat > "${MOCKBIN}/npm" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${NPM_ARGS_FILE}"
MOCK
  chmod +x "${MOCKBIN}/npm"
}

# Stub prettier on PATH so `command -v prettier` succeeds.
_stub_prettier() {
  cat > "${MOCKBIN}/prettier" <<'MOCK'
#!/usr/bin/env bash
echo "1.2.3"
MOCK
  chmod +x "${MOCKBIN}/prettier"
}

@test "install.sh: installs prettier via npm when prettier is missing" {
  _setup_sandbox
  _mock_npm

  run bash "${INSTALL_SH}"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g prettier$'
}

@test "install.sh: skips npm install when prettier is already present" {
  _setup_sandbox
  _mock_npm
  _stub_prettier

  run bash "${INSTALL_SH}"

  assert_success
  [ ! -s "${NPM_ARGS_FILE}" ]
}
