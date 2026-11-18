#!/usr/bin/env bats
# shellcheck disable=SC2034  # fixtures consumed by the tests that load this
# =============================================================================
# src/agentic/datasources/tests/datasources_test_helper.bash
# Shared setup, teardown and fixtures for the datasources test files.
#
# Split from datasources_tests.bats so its four themes can run as separate BATS
# files (bats parallelises across files only, and this module was among the
# largest files in the suite). The docker/validator/curl stubs and the catalogue
# fixtures live here once; each file loads this.
#
# No docker and no network. Where a "usable" datasource is needed the fixtures
# use sqlite, which has no server to reach; where an unreachable one is needed
# they use port 1, which is reserved and never listening.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Four levels: tests -> datasources -> agentic -> src -> repo root.
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  MODULE_DIR="${PROJECT_ROOT}/src/agentic/datasources"

  SANDBOX_DIR="$(mktemp -d)"
  PROJECT_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  # The real docker (if any), captured before the stub below is prepended, for
  # the container e2e that must talk to a real daemon.
  ORIGINAL_PATH="${PATH}"
  REAL_DOCKER="$(command -v docker || true)"

  # The sandbox plays the devbot root: it holds the fixture global config and
  # receives the rendered artifacts. Shared helpers are resolved beside the
  # module (not under DEV_BOT_ROOT), so they need no copying here.
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  RUNTIME_DIR="${SANDBOX_DIR}/storage/datasources"
  CONF_DIR="${RUNTIME_DIR}/conf"

  # The real validator runs the pinned toolbox image in docker. These tests
  # stay docker-free, so the oracle is stubbed by default with a passthrough —
  # test_validate_catalogue.py covers its logic and test-render.sh's own tests
  # cover the wiring; the real container path is the committed e2e.
  VALIDATOR_STUB="${SANDBOX_DIR}/validator-passthrough.py"
  cat > "${VALIDATOR_STUB}" <<'PY'
import json, sys
json.dump(json.load(sys.stdin), sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${VALIDATOR_STUB}"

  # No unit test may touch a real docker daemon or the developer's running
  # gateway: stub `docker` so the post-publish check sees "not running" and
  # skips. The rollback test prepends its own stub to override this.
  FAKEBIN="${SANDBOX_DIR}/fakebin"
  mkdir -p "${FAKEBIN}"
  cat > "${FAKEBIN}/docker" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "inspect" ]] && echo false
exit 0
SH
  chmod +x "${FAKEBIN}/docker"
  export PATH="${FAKEBIN}:${PATH}"

  # Nothing may leak in from the developer's own shell, or a test that expects
  # a variable to be missing would pass for the wrong reason.
  unset SQLITE_DATABASE MYSQL_HOST MYSQL_USER MYSQL_PASSWORD DB_PASS
}

teardown() {
  rm -rf "${SANDBOX_DIR}" "${PROJECT_DIR}" 2>/dev/null || true
}

# A docker stub that reports the toolbox image as absent (`image inspect` fails)
# so the pre-pull notice fires; records calls like _record_docker.
_docker_without_toolbox_image() {
  DOCKER_LOG="${SANDBOX_DIR}/docker-calls.log"
  mkdir -p "${SANDBOX_DIR}/recbin"
  cat > "${SANDBOX_DIR}/recbin/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_LOG}"
[[ "\$1" == "inspect" ]] && echo false
[[ "\$1" == "image" && "\$2" == "inspect" ]] && exit 1
exit 0
SH
  chmod +x "${SANDBOX_DIR}/recbin/docker"
  export PATH="${SANDBOX_DIR}/recbin:${PATH}"
}

# A pass-through validator that also records the arguments it was given, so a
# test can see whether render.sh forwarded --skip-canary.
_recording_validator() {
  VALIDATOR_ARGS_LOG="${SANDBOX_DIR}/validator-args.log"
  : > "${VALIDATOR_ARGS_LOG}"
  local stub="${SANDBOX_DIR}/recording-validator.py"
  cat > "${stub}" <<PY
import json, sys
with open("${VALIDATOR_ARGS_LOG}", "a", encoding="utf-8") as log:
    log.write(" ".join(sys.argv[1:]) + "\\n")
json.dump(json.load(sys.stdin), sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${stub}"
}

# ── fixtures ─────────────────────────────────────────────────────────────────

# The global catalogue. The argument is JSON, so it is passed single-quoted and
# a "${VAR}" reference survives to the config file untouched.
_catalogue() {
  printf '{"datasources": %s}\n' "$1" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

# The global catalogue plus the machine's known-project list. A project listed
# here demands its sidecars even when the project being rendered does not.
_catalogue_projects() {
  printf '{"datasources": %s, "projects": %s}\n' "$1" "$2" \
    > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

_project_config() {
  local datasources="$1" modules="${2:-}" harness="${3:-}"
  [[ -z "${modules}" ]] && modules='{}'
  if [[ -n "${harness}" ]]; then
    printf '{"harness": "%s", "modules": %s, "datasources": %s}\n' \
      "${harness}" "${modules}" "${datasources}" > "${PROJECT_DIR}/.devbot.project.jsonc"
    return 0
  fi
  printf '{"modules": %s, "datasources": %s}\n' "${modules}" "${datasources}" \
    > "${PROJECT_DIR}/.devbot.project.jsonc"
}

# A datasource that is usable with no environment at all: a literal path, and
# no server to reach.
_sqlite_catalogue() {
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } } }'
}

# A docker stub that records every invocation, so a test can tell whether the
# gateway was actually started. Prepended over the setup stub.
_record_docker() {
  DOCKER_LOG="${SANDBOX_DIR}/docker-calls.log"
  mkdir -p "${SANDBOX_DIR}/recbin"
  cat > "${SANDBOX_DIR}/recbin/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_LOG}"
[[ "\$1" == "inspect" ]] && echo false
exit 0
SH
  chmod +x "${SANDBOX_DIR}/recbin/docker"
  export PATH="${SANDBOX_DIR}/recbin:${PATH}"
}

# Pretend a live devbot session is serving <project_dir>: a session file whose
# flock a background holder keeps for the duration of the test.
_live_session() {
  local sessions="${DEV_BOT_ROOT}/storage/run/sessions"
  mkdir -p "${sessions}"
  printf '%s\n' "$1" >"${sessions}/session-4242"
  # The lock must outlive the reload, not just the usual case: a loaded suite
  # stretches that render past the 5 s a tight window allowed.
  ( exec 218<>"${sessions}/session-4242"; flock -x 218; sleep 60 ) &
  sleep 0.3
}

# A docker stub that records calls AND reports the given running sidecars on
# `ps` (none when called with no names).
_docker_reporting_running_sidecars() {
  DOCKER_LOG="${SANDBOX_DIR}/docker-calls.log"
  local names="" name
  for name in "$@"; do names+="dev-bot-datasources-${name} "; done
  mkdir -p "${SANDBOX_DIR}/runbin"
  cat > "${SANDBOX_DIR}/runbin/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_LOG}"
case "\$1" in
  inspect) echo false ;;
  ps) printf '%s\n' ${names} ;;
esac
exit 0
SH
  chmod +x "${SANDBOX_DIR}/runbin/docker"
  export PATH="${SANDBOX_DIR}/runbin:${PATH}"
}

# A docker stub whose `inspect` reports the gateway as RUNNING, so the reload
# sees a container it must not restart. `logs` stays silent: no reload
# rejection to find.
_docker_with_running_gateway() {
  DOCKER_LOG="${SANDBOX_DIR}/docker-calls.log"
  mkdir -p "${SANDBOX_DIR}/upbin"
  cat > "${SANDBOX_DIR}/upbin/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_LOG}"
case "\$1" in
  inspect) echo true ;;
esac
exit 0
SH
  chmod +x "${SANDBOX_DIR}/upbin/docker"
  export PATH="${SANDBOX_DIR}/upbin:${PATH}"
}

# A curl stub that answers a `tools/list` probe the way a SERVING toolset does:
# a result carrying the tool declared for that source. The source name is read
# from the URL, so the stub also proves the probe targets the right endpoint.
# Records the argv it was handed — the URL is part of the contract.
_record_curl() {
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/curlbin"
  cat > "${SANDBOX_DIR}/curlbin/curl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CURL_LOG}"
url=""
for arg in "\$@"; do
  case "\$arg" in */mcp/*) url="\$arg" ;; esac
done
printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"%s_execute_sql"}]}}\n' "\${url##*/}"
exit 0
SH
  chmod +x "${SANDBOX_DIR}/curlbin/curl"
  export PATH="${SANDBOX_DIR}/curlbin:${PATH}"
}

# A curl stub that answers the way toolbox does for a toolset it never loaded:
# HTTP 200 with a JSON-RPC error body. Status alone would read as success.
_record_missing_toolset_curl() {
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/curlbin"
  cat > "${SANDBOX_DIR}/curlbin/curl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CURL_LOG}"
printf '{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"toolset does not exist"}}\n'
exit 0
SH
  chmod +x "${SANDBOX_DIR}/curlbin/curl"
  export PATH="${SANDBOX_DIR}/curlbin:${PATH}"
}

# A curl stub standing in for a STATEFUL MCP server: it issues a session id on
# initialize and rejects a tools/list that does not carry it. Toolbox 1.11.0 is
# stateless, but a sidecar built on the stateful transport is not — a bare
# tools/list would read as "not serving" for a perfectly healthy server.
_record_stateful_curl() {
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/statefulbin"
  cat > "${SANDBOX_DIR}/statefulbin/curl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CURL_LOG}"
case "\$*" in
  *tools/list*)
    if printf '%s' "\$*" | grep -qi 'mcp-session-id: s-42'; then
      printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"scratch_execute_sql"}]}}\n'
    else
      printf '{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"missing session"}}\n'
    fi
    ;;
  *)
    printf 'HTTP/1.1 200 OK\r\nMcp-Session-Id: s-42\r\nContent-Type: application/json\r\n\r\n{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}\n'
    ;;
esac
exit 0
SH
  chmod +x "${SANDBOX_DIR}/statefulbin/curl"
  export PATH="${SANDBOX_DIR}/statefulbin:${PATH}"
}

# A curl stub for a fully compliant stateful server: it issues a session id,
# refuses tools/list until `notifications/initialized` arrives on that session,
# and records the DELETE that closes it.
_record_compliant_stateful_curl() {
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  STATE="${SANDBOX_DIR}/curl-initialized"
  mkdir -p "${SANDBOX_DIR}/compliantbin"
  cat > "${SANDBOX_DIR}/compliantbin/curl" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${CURL_LOG}"
case "\$*" in
  *notifications/initialized*) : > "${STATE}"; printf '{}\n' ;;
  *tools/list*)
    if [[ -f "${STATE}" ]]; then
      printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"scratch_execute_sql"}]}}\n'
    else
      printf '{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"not initialized"}}\n'
    fi
    ;;
  *DELETE*) printf '{}\n' ;;
  *) printf 'HTTP/1.1 200 OK\r\nMcp-Session-Id: s-7\r\nContent-Type: application/json\r\n\r\n{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}\n' ;;
esac
exit 0
SH
  chmod +x "${SANDBOX_DIR}/compliantbin/curl"
  export PATH="${SANDBOX_DIR}/compliantbin:${PATH}"
}

