#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/env_load_tests.bats
# _devbot_load_env_file: a .env template must not erase the environment.
#
# The shipped .env.dist lists every optional credential as `NAME=` (empty). A
# plain `set -a; source .env` reassigns those names to "", so a value exported
# in the operator's shell is silently discarded — one boot warned that five
# datasource variables were unset while every one of them was exported in
# .bashrc, and the sidecars started without credentials.
#
# Rules under test:
#   * a blank placeholder leaves a non-empty inherited value alone,
#   * a real value in the file still wins over the environment,
#   * a clear the FILE performs after setting a value is its own business,
#   * everything loaded is exported (compose interpolation and child processes
#     read the environment, not shell-local variables).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  FUNCTIONS="${PROJECT_ROOT}/src/_shared/functions.sh"
  ENV_FILE="${BATS_TEST_TMPDIR}/.env"
}

# Run a snippet in a fresh, EMPTY shell with the shared library loaded — `env -i`
# so nothing leaks in from the developer's own profile (a real MONGODB_PROD_DSN
# would otherwise satisfy a test that expects an unconfigured placeholder).
# Arguments are VAR=value assignments for the inherited environment.
_env_shell() {
  run env -i PATH="${PATH}" "$@" bash -c "source '${FUNCTIONS}'; _devbot_load_env_file '${ENV_FILE}'; ${SNIPPET}"
  assert_success
}

@test "a blank placeholder does not erase an exported value" {
  printf 'AWS_KEY=\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_KEY}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-shell"
}

@test "a quoted-empty placeholder does not erase an exported value" {
  printf 'AWS_KEY=""\nAWS_SECRET=%s\n' "''" >"${ENV_FILE}"

  SNIPPET='printf "%s|%s" "${AWS_KEY}" "${AWS_SECRET}"'
  _env_shell AWS_KEY=from-shell AWS_SECRET=also-from-shell
  assert_output "from-shell|also-from-shell"
}

@test "a \${VAR} expansion later in the file sees the inherited value" {
  # The real symptom: the template derives AWS_PROD_RO_ACCESS_KEY_ID from
  # ${AWS_KEY}, so blanking AWS_KEY emptied the derived value too. Restoring
  # values AFTER sourcing cannot fix this — it expanded while the file was read.
  printf 'AWS_KEY=\nAWS_PROD_RO_ACCESS_KEY_ID=${AWS_KEY}\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_PROD_RO_ACCESS_KEY_ID}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-shell"
}

@test "a real value in the file still wins over the environment" {
  printf 'AWS_KEY=from-file\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_KEY}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-file"
}

@test "a blank the file performs after its own value still clears it" {
  # Only an UNFILLED placeholder is neutralised. A var the file sets and then
  # clears is a deliberate statement and must survive.
  printf 'DATASOURCES_PORT=18600\nDATASOURCES_PORT=\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${DATASOURCES_PORT}"'
  _env_shell DATASOURCES_PORT=18510
  assert_output ""
}

@test "a blank placeholder with nothing inherited stays empty, under set -u" {
  # A placeholder for a source the operator does not use must not abort the
  # boot: the name is still assigned (empty), never left unset.
  printf 'MONGODB_PROD_DSN=\n' >"${ENV_FILE}"

  SNIPPET='set -u; printf "[%s]" "${MONGODB_PROD_DSN}"'
  _env_shell
  assert_output "[]"
}

@test "loaded values are exported, so a child process sees them" {
  # compose interpolates ${VAR} and the python renderers read os.environ: the
  # value has to leave this shell.
  printf 'AWS_KEY=from-file\n' >"${ENV_FILE}"

  SNIPPET='bash -c "printf %s \"\$AWS_KEY\""'
  _env_shell
  assert_output "from-file"
}

@test "a missing .env file is a silent no-op" {
  rm -f "${ENV_FILE}"

  SNIPPET='printf ok'
  _env_shell
  assert_output "ok"
}

@test "an environment name holding spaces survives intact" {
  # A blank line is replaced by a self-reference, so the inherited value must
  # pass through unmangled — quotes, spaces and `$` included.
  printf 'MARIADB_PROD_PASSWORD=\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${MARIADB_PROD_PASSWORD}"'
  _env_shell 'MARIADB_PROD_PASSWORD=p a$s"word'
  assert_output 'p a$s"word'
}

# ── The rewrite's own branches ──────────────────────────────────────────────
# Each of these is load-bearing in the awk program and had no coverage.

@test "an exported placeholder keeps the inherited value" {
  printf 'export AWS_KEY=\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_KEY}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-shell"
}

@test "a blank carrying a trailing comment still keeps the inherited value" {
  printf 'AWS_KEY=   # read-only identity\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_KEY}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-shell"
}

@test "a CRLF blank line still counts as blank" {
  # A .env written on Windows: the trailing \r must not read as a value, or the
  # placeholder would be sourced as-is and blank the variable a second time.
  printf 'AWS_KEY=\r\n' >"${ENV_FILE}"

  SNIPPET='printf "%s" "${AWS_KEY}"'
  _env_shell AWS_KEY=from-shell
  assert_output "from-shell"
}

@test "a failing awk degrades to a plain source, never an empty environment" {
  # aws-mcp-proxy.sh resolves credentials through this loader while the harness
  # spawns it, so a broken awk must fall back to the old behaviour (which loads
  # the file, blanks and all) rather than load nothing.
  printf 'AWS_KEY=\nAWS_SECRET=from-file\n' >"${ENV_FILE}"
  local shim="${BATS_TEST_TMPDIR}/noawk"
  mkdir -p "${shim}"
  printf '#!/usr/bin/env bash\nexit 1\n' >"${shim}/awk"
  chmod +x "${shim}/awk"

  run env -i PATH="${shim}:${PATH}" AWS_KEY=from-shell bash -c \
    "source '${FUNCTIONS}'; _devbot_load_env_file '${ENV_FILE}'; printf '%s|%s' \"\${AWS_KEY:-UNSET}\" \"\${AWS_SECRET:-UNSET}\""
  assert_success
  assert_output "UNSET|from-file"
}

@test "an allexport caller is left with allexport on" {
  printf 'AWS_KEY=from-file\n' >"${ENV_FILE}"

  run env -i PATH="${PATH}" bash -c \
    "source '${FUNCTIONS}'; set -a; _devbot_load_env_file '${ENV_FILE}'; [[ -o allexport ]] && printf on || printf off"
  assert_success
  assert_output "on"
}
