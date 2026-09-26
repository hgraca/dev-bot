#!/usr/bin/env bats
# =============================================================================
# src/agentic/format-yml/tests/install_tests.bats
# Tests for src/agentic/format-yml/install.sh and update.sh — the prettier guard's
# skip / install / update paths, and the verify-after-install step, with no real
# npm side effects.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/src/agentic/format-yml/install.sh"
  UPDATE_SH="${PROJECT_ROOT}/src/agentic/format-yml/update.sh"
}

_setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  export MOCKBIN
  export NPM_ARGS_FILE="${SANDBOX}/npm.args"
  : > "${NPM_ARGS_FILE}"
  # A PATH with only the dirs holding python3/node/npm plus mockbin. Any dir that
  # ALSO holds a prettier binary is skipped: on a single-prefix layout (nvm,
  # /usr/local/bin, a container) npm and prettier share a bin dir, and including
  # it would make `command -v prettier` succeed — silently defeating the
  # "prettier is missing" setup this file depends on.
  local dirs=""
  local bin d
  for bin in python3 node npm; do
    d="$(dirname "$(command -v "$bin")")"
    if [ -x "$d/prettier" ]; then
      continue
    fi
    case ":$dirs:" in
      *":$d:"*) ;;
      *) dirs="${dirs}:${d}" ;;
    esac
  done
  export PATH="${MOCKBIN}:${dirs#:}"
}

# Stub node, so `command -v node` passes even when its dir was skipped above.
_stub_node() {
  cat > "${MOCKBIN}/node" <<'MOCK'
#!/usr/bin/env bash
echo "v22.0.0"
MOCK
  chmod +x "${MOCKBIN}/node"
}

# Mock npm that records its invocation instead of installing anything.
_mock_npm() {
  cat > "${MOCKBIN}/npm" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${NPM_ARGS_FILE}"
MOCK
  chmod +x "${MOCKBIN}/npm"
}

# The same mock, but landing a prettier the way a real `npm install -g` would —
# so the scripts' post-install verification has something to find.
_mock_npm_installing() {
  _mock_npm
  cat >> "${MOCKBIN}/npm" <<'MOCK'
printf '#!/usr/bin/env bash\necho 1.2.3\n' > "${MOCKBIN}/prettier"
chmod +x "${MOCKBIN}/prettier"
MOCK
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
  _stub_node
  _mock_npm_installing

  run bash "${INSTALL_SH}"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g prettier$'
}

@test "install.sh: skips npm install when prettier is already present" {
  _setup_sandbox
  _stub_node
  _mock_npm
  _stub_prettier

  run bash "${INSTALL_SH}"

  assert_success
  [ ! -s "${NPM_ARGS_FILE}" ]
}

@test "install.sh: fails when prettier is still missing after npm" {
  # A failing command substitution does not abort under `set -e`, so without the
  # explicit check the script would report success for an unusable install.
  _setup_sandbox
  _stub_node
  _mock_npm

  run bash "${INSTALL_SH}"

  assert_failure
  assert_output --partial "prettier is still not on PATH"
}

@test "update.sh: installs prettier when it is missing" {
  # Updating must not dead-end on a missing prettier — it installs it.
  _setup_sandbox
  _stub_node
  _mock_npm_installing

  run bash "${UPDATE_SH}"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g prettier$'
}

@test "update.sh: updates prettier when it is already present" {
  _setup_sandbox
  _stub_node
  _mock_npm
  _stub_prettier

  run bash "${UPDATE_SH}"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^update -g prettier$'
}

@test "update.sh: fails when prettier is still missing after npm" {
  _setup_sandbox
  _stub_node
  _mock_npm

  run bash "${UPDATE_SH}"

  assert_failure
  assert_output --partial "prettier is still not on PATH"
}
