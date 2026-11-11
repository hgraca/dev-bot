#!/usr/bin/env bats
# =============================================================================
# src/agentic/datasources/tests/datasources_tests.bats
# Lifecycle tests for the datasources module.
#
# Covers the two shell behaviours that carry the design:
#
#   render.sh — the availability gate. Toolbox treats an unresolvable or
#               unreachable source as a FATAL startup error, so only usable
#               datasources may reach the gateway config. And the compose env
#               list must carry variable NAMES, never literals.
#   init.sh   — per-project wiring: a manifest for each selected datasource,
#               pruning for the deselected, and the harness gate.
#
# No docker and no network. Where a "usable" datasource is needed the fixtures
# use sqlite, which has no server to reach; where an unreachable one is needed
# they use port 1, which is reserved and never listening.
#
# Run from project root:
#   bats src/agentic/datasources/tests/datasources_tests.bats
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
  ( exec 218<>"${sessions}/session-4242"; flock -x 218; sleep 5 ) &
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

# ── install.sh never pulls the toolbox image ─────────────────────────────────
# install runs with `--all`, so a pull here downloads the gateway image for a
# machine that may never enable it. docker compose pulls it on first `up`, and
# bin/up.sh announces the download.

_install_toolbox_probe() {
  PULL_LOG="${SANDBOX_DIR}/docker-pulls.log"
  mkdir -p "${SANDBOX_DIR}/pullbin"
  cat > "${SANDBOX_DIR}/pullbin/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${PULL_LOG}"
if [[ "\$1" == "image" && "\$2" == "inspect" ]]; then exit 1; fi
exit 0
SH
  chmod +x "${SANDBOX_DIR}/pullbin/docker"
  export PATH="${SANDBOX_DIR}/pullbin:${PATH}"
}

@test "install: never pulls the toolbox image, with or without a declared datasource" {
  local catalogue
  for catalogue in empty declared; do
    _catalogue '{}'
    [[ "${catalogue}" == "declared" ]] && _sqlite_catalogue
    _install_toolbox_probe

    _recording_validator
    run bash "${MODULE_DIR}/install.sh"
    assert_success
    assert_output --partial "pulled by the module's up.sh on first use"
    # Declared sources used to reach the validator's canary, whose `docker run`
    # pulls the toolbox image. Install renders with the canary skipped instead.
    if [[ "${catalogue}" == "declared" ]]; then
      grep -q -- '--skip-canary' "${VALIDATOR_ARGS_LOG}" ||
        fail "install did not skip the toolbox canary (${catalogue} catalogue)"
    fi
    if [[ -f "${PULL_LOG}" ]] && grep -qE '^(pull|run) ' "${PULL_LOG}"; then
      fail "toolbox image pulled during install (${catalogue} catalogue)"
    fi
  done
}

# ── render.sh ────────────────────────────────────────────────────────────────

@test "render: DATASOURCES_CANARY_TIMEOUT is forwarded as --timeout" {
  # The readiness budget is per source and the canaries run in parallel, so a
  # slow remote handshake is a per-render cost the operator can raise without
  # editing the default.
  _sqlite_catalogue
  _recording_validator

  run env DATASOURCES_CANARY_TIMEOUT=20 bash "${MODULE_DIR}/render.sh"
  assert_success
  grep -q -- '--timeout 20' "${VALIDATOR_ARGS_LOG}" ||
    fail "render.sh did not forward DATASOURCES_CANARY_TIMEOUT"
}

@test "render: no --timeout is passed when the budget is not overridden" {
  # Unset must keep the validator's own DEFAULT_TIMEOUT, never an empty flag.
  _sqlite_catalogue
  _recording_validator

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  # The render line proves the validator actually ran, so the absence below is
  # a real absence and not an empty log.
  assert_output --partial "1/1 toolbox source(s) usable"
  refute grep -q -- '--timeout' "${VALIDATOR_ARGS_LOG}"
}

@test "render: a usable datasource becomes a source, a tool and a toolset" {
  _sqlite_catalogue

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1 toolbox source(s) usable"

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "kind: source"
  assert_output --partial "name: scratch"
  assert_output --partial "type: sqlite-execute-sql"
  assert_output --partial "kind: toolset"
}

@test "render: a literal is written inline and needs no environment" {
  _sqlite_catalogue

  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "database: '/data/scratch.db'"
}

@test "render: an unset \${VAR} reference keeps the datasource out" {
  # toolbox refuses to START on a missing variable, so letting this through
  # would take the whole shared gateway — and every project — down with it.
  # The reference is on a field with NO default: on a defaulted field (host,
  # port, database) an unset variable legitimately falls back to the default,
  # which the Python tests cover.
  _catalogue '{ "db": { "type": "mysql", "env": { "MYSQL_HOST": "127.0.0.1", "MYSQL_USER": "root", "MYSQL_PASSWORD": "${NOT_SET_ANYWHERE}" } } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "not usable"
  assert_output --partial "NOT_SET_ANYWHERE"

  run cat "${CONF_DIR}/tools.yaml"
  refute_output --partial "kind: source"
}

@test "render: a source the oracle rejects is dropped" {
  # The oracle decides what toolbox can initialize. Stub it to drop "db" and
  # report a reason, exactly as validate_catalogue.py does.
  local drop="${SANDBOX_DIR}/validator-drop-db.py"
  cat > "${drop}" <<'PY'
import json, sys
data = json.load(sys.stdin)
data.pop("db", None)
sys.stderr.write("INFO: datasource 'db' is not usable — unreachable: 127.0.0.1:1\n")
json.dump(data, sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${drop}"

  _catalogue '{ "db": { "type": "mysql", "env": { "MYSQL_HOST": "127.0.0.1", "MYSQL_PORT": "1", "MYSQL_USER": "root", "MYSQL_PASSWORD": "p" } } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "unreachable"

  run cat "${CONF_DIR}/tools.yaml"
  refute_output --partial "kind: source"
}

@test "render: points at reload when a declared source was dropped" {
  # The manifest survives the drop, so the user's next move is the toggle that
  # would fail. Name the command that fixes it, at the moment the decision is
  # made.
  local drop="${SANDBOX_DIR}/validator-drop-db.py"
  cat > "${drop}" <<'PY'
import json, sys
data = json.load(sys.stdin)
data.pop("db", None)
json.dump(data, sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${drop}"

  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } }, "db": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/db.db" } } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1 of 2 toolbox source(s) unusable now"
  assert_output --partial "devbot datasources reload"
}

@test "render: a healthy sidecar is not counted as a dropped source" {
  # Sidecars are their own servers and never appear in tools.yaml, so counting
  # the raw catalogue reported every one of them as dropped on every boot.
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } }, "search": { "type": "opensearch", "env": {} } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1 toolbox source(s) usable"
  refute_output --partial "unusable now"
}

@test "render: stays quiet about reload when every source is usable" {
  _sqlite_catalogue

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  refute_output --partial "devbot datasources reload"
}

@test "render: the compose env list carries references, never literals" {
  # The env list is rendered from the FULL catalogue, regardless of what the
  # oracle accepts. It must carry variable NAMES only: a literal value here
  # would put a host or credential into the compose file.
  _catalogue '{ "db": { "type": "mysql", "env": { "MYSQL_HOST": "db.internal", "MYSQL_PORT": "3306", "MYSQL_USER": "root", "MYSQL_PASSWORD": "${DB_PASS}" } } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run grep '^    environment:' "${RUNTIME_DIR}/docker-compose.yml"
  assert_success
  assert_output --partial "DB_PASS"
  # `db.internal` is a literal in the catalogue; if the renderer ever wrote
  # values instead of names it would appear here.
  refute_output --partial "db.internal"
}

@test "render: an invalid catalogue fails and leaves the working config alone" {
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success
  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  _catalogue '{ "db": { "type": "oracle", "env": {} } }'
  run bash "${MODULE_DIR}/render.sh"
  assert_failure
  assert_output --partial "unknown type"

  # The running gateway must still be reading the last good config.
  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
}

@test "render: an unreadable catalogue is an error and leaves the working config alone" {
  # A read failure must never look like "no datasources declared": collapsing
  # it to an empty catalogue is how an empty config once replaced a good one
  # and took every toolset down with it.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  printf 'this is not json\n' > "${SANDBOX_DIR}/.devbot.global.jsonc"

  run bash "${MODULE_DIR}/render.sh"
  assert_failure

  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
}

@test "render: a config without a datasources key writes an empty catalogue" {
  # Legitimately no datasources declared. This must still succeed and render
  # the empty config, so the read-integrity guard cannot deadlock a removal.
  printf '{"modules": {}}\n' > "${SANDBOX_DIR}/.devbot.global.jsonc"

  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "No datasources configured"
}

@test "render: an all-unusable catalogue publishes the empty config" {
  # Datasources are evaluated once, at startup: a source that is not usable now
  # is simply not loaded. Keeping the previous config instead would leave the
  # gateway pointed at sources it cannot initialize — which is fatal to it.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1"

  # Declared but env-incomplete (no SQLITE_DATABASE), so nothing is usable.
  _catalogue '{ "scratch": { "type": "sqlite", "env": {} } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "0/1 toolbox source(s) usable"

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "No datasources configured"
}

@test "render: an explicitly empty catalogue still publishes the empty config" {
  # The no-regression guard must not deadlock a deliberate removal.
  _catalogue '{}'

  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "No datasources configured"
}

@test "render: removing every datasource publishes the empty config" {
  # A removal AFTER a good config was published must still take effect.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  _catalogue '{}'
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "No datasources configured"
}

@test "render: a validator failure keeps the last good config" {
  # An oracle that cannot run (docker down, inconclusive, or a render bug) must
  # abort the render and leave the published config alone.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  local boom="${SANDBOX_DIR}/validator-boom.py"
  cat > "${boom}" <<'PY'
import sys
sys.stderr.write("ERROR: docker not found; cannot validate the catalogue\n")
sys.exit(2)
PY
  export DATASOURCES_VALIDATOR="${boom}"

  run bash "${MODULE_DIR}/render.sh"
  assert_failure

  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
}

@test "render: an unchanged config is not republished" {
  # Re-publishing identical content makes toolbox reload for nothing, and pays
  # the verification wait on every poll.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1"

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "config unchanged"
}

@test "render: a transient reload rejection does not roll back" {
  # `cp` rewrites in place, so toolbox can read a partial document mid-write and
  # report a source failure for a config that is actually fine. A rejection that
  # does not survive a second reload cycle must be ignored.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  # A changed catalogue, so the render publishes.
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/other.db" } } }'

  local fake="${SANDBOX_DIR}/transientbin"
  mkdir -p "${fake}"
  cat > "${fake}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  inspect) echo true ;;
  logs)
    # Reject on the first check only, like a mid-write read.
    if [[ ! -f "${FAKE_STATE}" ]]; then
      touch "${FAKE_STATE}"
      echo 'WARN "unable to initialize source \"x\": partial read"'
    fi
    ;;
esac
exit 0
SH
  chmod +x "${fake}/docker"

  run env PATH="${fake}:${PATH}" DATASOURCES_RELOAD_WAIT=0 \
    FAKE_STATE="${SANDBOX_DIR}/rejected.marker" bash "${MODULE_DIR}/render.sh"
  assert_success
  refute_output --partial "rolled back"
}

@test "render: a config the gateway rejects is rolled back" {
  # Fake docker: a gateway that is running and refuses the reload. The previous
  # config must be restored — toolbox would otherwise retry the bad file on
  # every poll interval.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  # A changed catalogue, so the render has something to publish.
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/other.db" } } }'

  local fake="${SANDBOX_DIR}/rejectbin"
  mkdir -p "${fake}"
  cat > "${fake}/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  inspect) echo true ;;
  logs) echo 'WARN "unable to initialize reloaded configs: unable to initialize source \"x\": boom"' ;;
esac
exit 0
SH
  chmod +x "${fake}/docker"

  run env PATH="${fake}:${PATH}" DATASOURCES_RELOAD_WAIT=0 bash "${MODULE_DIR}/render.sh"
  assert_failure
  assert_output --partial "rolled back"

  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
}

@test "render: a sidecar no project wants is left out of the compose" {
  # A sidecar is a heavyweight container of its own, so it is rendered only when
  # some project opts into it — a catalogue entry nobody wants must not appear.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '[]'

  run bash "${MODULE_DIR}/render.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${RUNTIME_DIR}/docker-compose.yml"
  refute_output --partial "container_name: dev-bot-datasources-search"
}

@test "render: a sidecar the current project wants is rendered" {
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '["search"]'

  run bash "${MODULE_DIR}/render.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${RUNTIME_DIR}/docker-compose.yml"
  assert_output --partial "container_name: dev-bot-datasources-search"
}

@test "render: a sidecar a listed project wants is rendered" {
  # The render-side universe is session-independent, so a project listed in
  # .devbot.global.jsonc::projects demands its sidecars even when the project
  # being rendered opts into nothing.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue_projects '{ "search": { "type": "opensearch", "env": {} } }' "[\"${other}\"]"
  _project_config '[]'

  run bash "${MODULE_DIR}/render.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${RUNTIME_DIR}/docker-compose.yml"
  assert_output --partial "container_name: dev-bot-datasources-search"

  rm -rf "${other}"
}

# ── init.sh ──────────────────────────────────────────────────────────────────

@test "init: a selected datasource gets a harness manifest" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "datasources-mariadb-dev"

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18510/mcp/mariadb-dev"'
}

@test "init: the opencode manifest ships disabled" {
  # The datasource gateways are optional per project, so the opencode manifest
  # opts the server out by default — one flag turns it on without a reinit.
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"enabled": false'
  [ ! -e "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json" ]
}

@test "init: the claude manifest ships enabled" {
  # .mcp.json has no per-server on/off, and _wire_mcp reads `enabled` as a
  # wire/don't-wire gate, so the claude manifest must stay true or the server
  # would silently disappear from that harness.
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '' 'claudecode'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"enabled": true'
  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: the opencode manifest carries the 60s MCP timeout by default" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 60000'
}

@test "init: a global config without a datasources key still writes the default timeout" {
  # The catalogue key is optional, so the reader yields nothing. That must not
  # reach the renderer as an empty stdin, which it rejects as "no catalogue".
  printf '{}\n' >"${SANDBOX_DIR}/.devbot.global.jsonc"
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 60000'
}

@test "init: a datasource's mcp_timeout_ms overrides the default" {
  _catalogue '{ "mariadb-dev": { "type": "mysql", "env": {}, "mcp_timeout_ms": 300000 } }'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 300000'
}

@test "init: the claude manifest carries no timeout" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json"
  assert_success
  refute_output --partial '"timeout"'
}

@test "init: an unusable mcp_timeout_ms fails loudly" {
  _catalogue '{ "mariadb-dev": { "type": "mysql", "env": {}, "mcp_timeout_ms": "300000" } }'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "mcp_timeout_ms"
}

@test "init: selecting nothing prunes the manifest" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "none selected"
  assert_output --partial "pruned mariadb-dev"

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: deselecting also unregisters the harness key" {
  # The harness merges manifests append-only, so removing the manifest alone
  # left a live server for a datasource the project had dropped.
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  cat > "${PROJECT_DIR}/opencode.jsonc" <<'JSON'
{
  "mcp": {
    "datasources-mariadb-dev": { "type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev" },
    "mdctx": { "type": "remote", "url": "http://127.0.0.1:18501/mcp" }
  }
}
JSON

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/opencode.jsonc"
  refute_output --partial "datasources-mariadb-dev"
  # A server this module does not own must be left alone.
  assert_output --partial "mdctx"
}

@test "init: the manifest URL follows a DATASOURCES_PORT from .env" {
  # The manifest must point where the gateway will listen. bin/init.sh does not
  # read the repo .env itself, so init has to load it before building the URL —
  # otherwise a configured port leaves every manifest on the default one.
  _sqlite_catalogue
  _project_config '["scratch"]'
  printf 'DATASOURCES_PORT=18600\n' > "${SANDBOX_DIR}/.env"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-scratch.mcp.json"
  assert_output --partial "127.0.0.1:18600/mcp/scratch"
}

@test "init: a selection absent from the catalogue is warned about" {
  _catalogue '{}'
  _project_config '["typo-db"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "not declared"
}

@test "init: nothing is written for the unselected harness" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '' 'claudecode'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: a sidecar datasource points at its own listener, not the gateway" {
  # A sidecar is served by its own http container, so its manifest URL carries
  # the port render_compose.py allocated — the same allocation the service uses.
  _catalogue '{"hotels": {"type": "mysql", "env": {}}, "search": {"type": "opensearch", "env": {}}}'
  _project_config '["hotels", "search"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-hotels.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18510/mcp/hotels"'

  run cat "${PROJECT_DIR}/.opencode/datasources-search.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'

  _project_config '["hotels", "search"]' '' 'claudecode'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.claude/datasources-search.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'
}

@test "init: deselecting a sidecar prunes its manifest" {
  _catalogue '{"search": {"type": "opensearch", "env": {}}}'
  _project_config '["search"]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  [ -f "${PROJECT_DIR}/.opencode/datasources-search.mcp.json" ]

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-search.mcp.json" ]
}

@test "init: an undemanded sidecar does not shift the demanded one's port" {
  # `alpha` sorts before `search`, so an unfiltered port map would give search
  # 18521 — a URL that does not match the compose, which renders only search.
  _catalogue '{"alpha": {"type": "opensearch", "env": {}}, "search": {"type": "opensearch", "env": {}}}'
  _project_config '["search"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-search.mcp.json"
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'
}

# ── down.sh ──────────────────────────────────────────────────────────────────

@test "down: never waits for the lifecycle lock while the registry lock is held" {
  # The last-session teardown calls this with the registry lock held, while up.sh
  # holds the lifecycle lock and waits for the registry. Blocking here would
  # deadlock both until their caps expire.
  _catalogue '{}'
  mkdir -p "${RUNTIME_DIR}/conf"
  printf 'services:\n  datasources-mcp:\n    image: x\n' > "${RUNTIME_DIR}/docker-compose.yml"
  _record_docker
  ( exec 205>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 205; sleep 5 ) &
  sleep 0.3

  local started=${SECONDS}
  run env _DEVBOT_REGISTRY_LOCK_HELD=1 DATASOURCES_LOCK_WAIT=60 \
    bash "${MODULE_DIR}/down.sh"
  local elapsed=$(( SECONDS - started ))
  assert_success
  [ "${elapsed}" -lt 5 ]
  grep -q 'compose .* down' "${DOCKER_LOG}"
}

@test "down: waits for the lifecycle lock but never hangs a teardown" {
  # Teardown must not pull the gateway from under a reload that is verifying it
  # — but a session exit must never hang, so an unavailable lock warns and
  # proceeds rather than skipping the stop.
  _catalogue '{}'
  mkdir -p "${RUNTIME_DIR}/conf"
  printf 'services:\n  datasources-mcp:\n    image: x\n' > "${RUNTIME_DIR}/docker-compose.yml"
  _record_docker
  ( exec 205>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 205; sleep 5 ) &
  sleep 0.3

  run env DATASOURCES_LOCK_WAIT=0 bash "${MODULE_DIR}/down.sh"
  assert_success
  assert_output --partial "stopping anyway"
  grep -q 'compose .* down' "${DOCKER_LOG}"
}

@test "down: no generated compose file is a clean no-op" {
  run bash "${MODULE_DIR}/down.sh"
  assert_success
  assert_output --partial "nothing to stop"
}

# ── up.sh ────────────────────────────────────────────────────────────────────

@test "up: waits for a lifecycle run in flight, then converges" {
  # The boot is the authoritative convergence for its own project — a session
  # registers before invoking this script, so once the lock is had its sidecar
  # demand is visible. Skipping would let the session start unserved.
  _sqlite_catalogue
  _record_docker
  mkdir -p "${RUNTIME_DIR}"
  ( exec 200>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 200; sleep 2 ) &
  sleep 0.3

  local started=${SECONDS}
  run env DATASOURCES_PORT=1 DATASOURCES_BOOT_LOCK_WAIT=20 DEV_BOT_MCP_WAIT_TRIES=1 \
    bash "${MODULE_DIR}/up.sh"
  local elapsed=$(( SECONDS - started ))
  assert_success
  refute_output --partial "still in progress"
  grep -q 'up -d --no-deps datasources-mcp' "${DOCKER_LOG}"
  [ "${elapsed}" -ge 1 ]
}

@test "up: warns, and does not claim a clean start, when the lock stays held" {
  # Only a genuinely stuck run reaches the cap; the boot must not pretend it
  # converged the datasources then.
  _sqlite_catalogue
  _record_docker
  mkdir -p "${RUNTIME_DIR}"
  ( exec 200>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 200; sleep 5 ) &
  sleep 0.3

  run env DATASOURCES_PORT=1 DATASOURCES_BOOT_LOCK_WAIT=0 DEV_BOT_MCP_WAIT_TRIES=1 \
    bash "${MODULE_DIR}/up.sh"
  assert_success
  assert_output --partial "may not answer until the next start"
  refute grep -q 'up -d' "${DOCKER_LOG}"
}

@test "up: a failed render still starts on the last good config" {
  # A render failure (docker down, inconclusive validation) must not abort the
  # boot: the config already on disk keeps serving. Only an EMPTY on-disk
  # catalogue means there is nothing to serve, whatever the render did.
  _sqlite_catalogue
  mkdir -p "${CONF_DIR}"
  printf 'kind: source\nname: scratch\n' > "${CONF_DIR}/tools.yaml"
  _record_docker

  local boom="${SANDBOX_DIR}/validator-boom.py"
  cat > "${boom}" <<'PY'
import sys
sys.stderr.write("ERROR: docker not found; cannot validate the catalogue\n")
sys.exit(2)
PY
  export DATASOURCES_VALIDATOR="${boom}"

  # A dead port keeps the readiness check instant, and never touches a real
  # gateway.
  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  assert_output --partial "render failed; starting the gateway with the previous config"
  grep -q "up -d" "${DOCKER_LOG}"
}

@test "up: a failed render over an empty catalogue starts nothing" {
  # The render's exit status and the catalogue DISAGREE here, and this is the
  # case that matters: the render failed, but what is on disk is the empty
  # placeholder — exactly the zero-tool gateway the guard exists to prevent.
  _catalogue '{}'
  mkdir -p "${CONF_DIR}"
  printf '# No datasources configured in .devbot.global.jsonc.\n' > "${CONF_DIR}/tools.yaml"
  _record_docker

  local boom="${SANDBOX_DIR}/validator-boom.py"
  cat > "${boom}" <<'PY'
import sys
sys.exit(2)
PY
  export DATASOURCES_VALIDATOR="${boom}"

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  assert_output --partial "no usable datasources; gateway not started"
  refute grep -q "up -d" "${DOCKER_LOG}"
}

@test "up: an empty catalogue does not start the gateway" {
  # Nothing to serve: a successfully rendered catalogue with no sources means
  # zero tools, so the gateway is pure cost — and on macOS/Windows Docker
  # Desktop it is unreachable anyway (host networking is a Linux capability).
  _catalogue '{}'
  _record_docker

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  assert_output --partial "no usable datasources; gateway not started"

  refute grep -q "up -d" "${DOCKER_LOG}"
}

@test "up: announces a missing toolbox image before the gateway pull" {
  # The gateway's compose is generated under storage/, so bin/up.sh's notice
  # cannot cover this download — the module has to say it here, before compose
  # starts pulling a large image.
  _sqlite_catalogue
  _docker_without_toolbox_image

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  assert_output --partial "not present locally"
  assert_output --partial "downloading now"
  grep -q "up -d --no-deps datasources-mcp" "${DOCKER_LOG}"
}

@test "up: says nothing about the image when it is already present" {
  _sqlite_catalogue
  _record_docker   # `image inspect` succeeds → the image is present

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  refute_output --partial "not present locally"
}

@test "up: renders through the toolbox oracle, never skipping the canary" {
  # The skip exists for install only; up must still validate against the real
  # toolbox, or an unusable source would take the gateway down.
  _sqlite_catalogue
  _recording_validator

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  refute grep -q -- '--skip-canary' "${VALIDATOR_ARGS_LOG}"
}

@test "up: stays silent about the image when the docker daemon is unreachable" {
  # `docker image inspect` also fails when the daemon is down or the socket is
  # denied, but nothing can be downloaded then — compose reports the real error,
  # and a "downloading now" would mislead.
  _sqlite_catalogue
  mkdir -p "${SANDBOX_DIR}/nodaemon"
  cat > "${SANDBOX_DIR}/nodaemon/docker" <<SH
#!/usr/bin/env bash
[[ "\$1" == "info" ]] && exit 1
exit 0
SH
  chmod +x "${SANDBOX_DIR}/nodaemon/docker"
  export PATH="${SANDBOX_DIR}/nodaemon:${PATH}"

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success
  refute_output --partial "not present locally"
}

@test "up: bounds the image probe so a wedged daemon cannot hang the boot" {
  # The probes sit on the `devbot up` critical path; an unresponsive socket must
  # hit the watchdog rather than block startup, and a timeout never announces a
  # download that is not happening.
  _sqlite_catalogue
  mkdir -p "${SANDBOX_DIR}/slowbin"
  cat > "${SANDBOX_DIR}/slowbin/docker" <<SH
#!/usr/bin/env bash
if [[ "\$1" == "info" ]]; then sleep 30; fi
exit 0
SH
  chmod +x "${SANDBOX_DIR}/slowbin/docker"
  export PATH="${SANDBOX_DIR}/slowbin:${PATH}"

  local started=${SECONDS}
  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_DOCKER_PROBE_TIMEOUT=1 \
    bash "${MODULE_DIR}/up.sh"
  local elapsed=$(( SECONDS - started ))

  assert_success
  refute_output --partial "not present locally"
  [ "${elapsed}" -lt 20 ]
}

@test "up: a usable datasource still starts the gateway" {
  _sqlite_catalogue
  _record_docker

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success

  grep -q "up -d" "${DOCKER_LOG}"
}

@test "up: a sidecar-only catalogue starts the sidecar, not the gateway" {
  # A sidecar has no toolbox source, so the gateway has nothing to serve — but
  # the sidecar's own service must still be started. The project dir is what
  # demands it, so up.sh must be told which project it is serving.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '["search"]'
  _record_docker

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success

  grep -q "up -d --build search" "${DOCKER_LOG}"
  # The gateway was not brought up — render.sh's readiness `inspect` is not a start.
  refute grep -qE 'up -d.*datasources-mcp' "${DOCKER_LOG}"
}

@test "up: starts a sidecar when a live session demands it" {
  # `other` is a known project that opts into the sidecar, and a live session is
  # serving it — so the sidecar runs even though the project being booted wants
  # nothing.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue_projects '{ "search": { "type": "opensearch", "env": {} } }' "[\"${other}\"]"
  _project_config '[]'
  _live_session "${other}"
  _record_docker

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  grep -q "up -d --build search" "${DOCKER_LOG}"

  rm -rf "${other}"
}

@test "up: does not start a sidecar no live session demands" {
  # The sidecar is rendered (a known project opts into it) but no session is
  # serving that project, so starting it would be pure cost.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue_projects '{ "search": { "type": "opensearch", "env": {} } }' "[\"${other}\"]"
  _project_config '[]'
  _record_docker

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  refute grep -q "up -d --build search" "${DOCKER_LOG}"

  rm -rf "${other}"
}

@test "up: stops a running sidecar no live session demands" {
  # A leftover from an earlier session must not idle for a project nobody has
  # open: the reconcile stops it.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '[]'
  _docker_reporting_running_sidecars search

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  grep -q "stop dev-bot-datasources-search" "${DOCKER_LOG}"
}

@test "up: two demanded sidecars are both started and neither is stopped" {
  # The real shape (observability wants opensearch AND s3). A separator mismatch
  # between the demand producer and the membership test would stop both.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["alpha", "beta"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue_projects \
    '{ "alpha": { "type": "opensearch", "env": {} }, "beta": { "type": "s3", "env": {} } }' \
    "[\"${other}\"]"
  _project_config '[]'
  _live_session "${other}"
  _docker_reporting_running_sidecars alpha beta

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  grep -q "up -d --build alpha" "${DOCKER_LOG}"
  grep -q "up -d --build beta" "${DOCKER_LOG}"
  refute grep -q "stop dev-bot-datasources-alpha" "${DOCKER_LOG}"
  refute grep -q "stop dev-bot-datasources-beta" "${DOCKER_LOG}"

  rm -rf "${other}"
}

@test "up: an unreadable catalogue stops no sidecar" {
  # A failed read must NOT read as "no demand": that would stop every sidecar a
  # live session is using.
  printf '{ this is not json\n' >"${SANDBOX_DIR}/.devbot.global.jsonc"
  _project_config '[]'
  _docker_reporting_running_sidecars search

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  refute grep -q "stop dev-bot-datasources-search" "${DOCKER_LOG}"
  assert_output --partial "leaving the running sidecars untouched"
}

@test "up: a sidecar the render gate refused is not started" {
  # A live project absent from the configured project list demands a sidecar
  # that was never rendered, and `up --build` on it would fail on every boot.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '[]'
  _live_session "${other}"
  _record_docker

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh" "${PROJECT_DIR}"
  assert_success
  refute grep -q "up -d --build search" "${DOCKER_LOG}"

  rm -rf "${other}"
}

@test "up: reaps a poller left behind by an older dev-bot" {
  # Refresh is no longer backgrounded, so a PID file can only be a leftover —
  # and a detached poller would keep rewriting the config for the new gateway.
  sleep 60 &
  local sleeper=$!
  mkdir -p "${RUNTIME_DIR}"
  printf '%s\n' "${sleeper}" > "${RUNTIME_DIR}/refresh.pid"

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success

  run kill -0 "${sleeper}"
  assert_failure

  [ ! -f "${RUNTIME_DIR}/refresh.pid" ]

  kill "${sleeper}" 2>/dev/null || true
}

@test "up: starts no background refresh of its own" {
  # Datasources are evaluated once, at startup — nothing is left running.
  _sqlite_catalogue

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 bash "${MODULE_DIR}/up.sh"
  assert_success

  [ ! -f "${RUNTIME_DIR}/refresh.pid" ]
}

@test "render: takes the lifecycle lock, so it cannot land mid-reload" {
  # A render WRITES the artifacts a reload is verifying against, so install.sh or
  # a direct render must wait like any other lifecycle run.
  _sqlite_catalogue
  mkdir -p "${RUNTIME_DIR}"
  ( exec 205>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 205; sleep 5 ) &
  sleep 0.3

  run env DATASOURCES_LOCK_WAIT=0 bash "${MODULE_DIR}/render.sh"
  assert_failure
  assert_output --partial "another lifecycle run is in progress"
}

@test "render: does not re-take the lock its caller already holds" {
  # up.sh and reload.sh hold it across their render; re-taking would deadlock.
  _sqlite_catalogue
  mkdir -p "${RUNTIME_DIR}"
  ( exec 205>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 205; sleep 5 ) &
  sleep 0.3

  run env DATASOURCES_LOCK_WAIT=0 DATASOURCES_LIFECYCLE_HELD=1 bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1 toolbox source(s) usable"
}

@test "render: skips when another render holds the lock" {
  command -v flock >/dev/null 2>&1 || skip "flock not available"
  mkdir -p "${RUNTIME_DIR}"
  flock "${RUNTIME_DIR}/render.lock" sleep 5 &
  local holder=$!
  sleep 0.3

  run env DATASOURCES_RENDER_LOCK_WAIT=0 bash "${MODULE_DIR}/render.sh"
  assert_failure
  assert_output --partial "another render is in progress"

  kill "${holder}" 2>/dev/null || true
}

# ── reload.sh ────────────────────────────────────────────────────────────────

@test "reload: hands the new config to a running gateway without a cold start" {
  # The whole point: a source that was unreachable at boot becomes servable
  # without a `devbot up`, so flipping it on in the harness stops failing. The
  # gateway is reconciled through compose (a no-op when nothing changed) rather
  # than torn down and rebuilt.
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  assert_output --partial "gateway reconciled with the rendered config"
  refute grep -qE 'compose .* down' "${DOCKER_LOG}"
  grep -q 'up -d --no-deps datasources-mcp' "${DOCKER_LOG}"
  # The source is proven on its own toolset URL, not just on the gateway root.
  grep -q '/mcp/scratch' "${CURL_LOG}"
}

@test "reload: a tool schema that declares an error property is still served" {
  # Only a TOP-LEVEL JSON-RPC `error` marks a failure. A tool may legitimately
  # have an input property called `error`, which a substring check would read as
  # a failed response and report a healthy server unavailable.
  _sqlite_catalogue
  _docker_with_running_gateway
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/schemabin"
  cat > "${SANDBOX_DIR}/schemabin/curl" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${CURL_LOG}"
printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"scratch_execute_sql","inputSchema":{"type":"object","properties":{"error":{"type":"string"}}}}]}}\\n'
SH
  chmod +x "${SANDBOX_DIR}/schemabin/curl"
  export PATH="${SANDBOX_DIR}/schemabin:${PATH}"

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "scratch answers"
}

@test "reload: refuses while another lifecycle run holds the lock" {
  # The render lock covers the publish only. A concurrent `devbot up` stops the
  # gateway BEFORE it renders, so a reload without a lifecycle lock could verify
  # a catalogue that another run has already replaced.
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_curl
  mkdir -p "${RUNTIME_DIR}"
  ( exec 200>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 200; sleep 5 ) &
  sleep 0.3

  run env DATASOURCES_PORT=1 DATASOURCES_LOCK_WAIT=0 DATASOURCES_RELOAD_WAIT=0 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  [ "$status" -eq 2 ]   # nothing applied, not "applied with a source down"
  assert_output --partial "another lifecycle run is in progress"
  refute grep -q 'up -d' "${DOCKER_LOG}"
}

@test "reload: starts the gateway a boot with every source down never started" {
  _sqlite_catalogue
  _record_docker   # inspect → false: no container
  _record_curl

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  grep -q "up -d --no-deps datasources-mcp" "${DOCKER_LOG}"
  assert_output --partial "gateway reachable"
}

@test "reload: a failed render aborts without touching the running config" {
  # Not survivable here, unlike at boot: the command exists to make a source
  # usable, and a silent partial answer is the trap it removes.
  _sqlite_catalogue
  _record_docker
  local boom="${SANDBOX_DIR}/validator-boom.py"
  cat > "${boom}" <<'PY'
import sys
sys.exit(2)
PY
  export DATASOURCES_VALIDATOR="${boom}"

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  [ "$status" -eq 2 ]   # the running config was never replaced
  assert_output --partial "reload aborted"
  refute grep -q 'up -d' "${DOCKER_LOG}"
}

@test "reload: starts a demanded sidecar that is not running" {
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '["search"]'
  _record_docker
  _record_curl

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  grep -q "up -d --build search" "${DOCKER_LOG}"
  assert_output --partial "sidecar 'search' started"
}

@test "reload: reconciles an already-running sidecar without rebuilding it" {
  # Running is not the same as matching: this render may have re-allocated the
  # sidecar's port, so `up` (which recreates only on a changed definition) runs.
  # The image is not rebuilt — that is boot work, not reload work.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '["search"]'
  _docker_reporting_running_sidecars search
  _record_curl

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  assert_output --partial "sidecar 'search' reconciled with the rendered config"
  grep -q "up -d search" "${DOCKER_LOG}"
  refute grep -q "up -d --build search" "${DOCKER_LOG}"
}

@test "reload: a live project's sidecar that was never rendered is unpublishable" {
  # The render's demand set is the configured project list plus this project; a
  # live project outside that list can select a sidecar with no compose service
  # at all, so its manifest points at nothing. Declared is not the same as
  # served.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '[]'
  _live_session "${other}"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "another live project selects what is still unpublishable"
  assert_output --partial "search ($(basename "${other}"))"

  rm -rf "${other}"
}

@test "reload: a published source that does not answer fails the command" {
  # Claiming success while the toolset endpoint is dead would recreate the
  # exact confusion this command exists to end.
  _sqlite_catalogue
  _record_docker   # gateway absent; the probe then hits a dead port for real

  run env DATASOURCES_PORT=1 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "is published but does not answer"
}

@test "reload: a toolset the gateway never loaded is not mistaken for success" {
  # toolbox answers `initialize` — and the HTTP status — for ANY /mcp/<name>,
  # including one it never loaded. Only the tools/list BODY distinguishes them,
  # and this is the exact failure the command exists to report.
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_missing_toolset_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "does not answer"
  assert_output --partial "is not served at"
}

@test "reload: carries the session id a stateful server issues" {
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_stateful_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  grep -qi 'mcp-session-id: s-42' "${CURL_LOG}"
}

@test "reload: accepts a pretty-printed tools/list body and declares the protocol" {
  # A sidecar may pretty-print its JSON, and the negotiated protocol version
  # belongs on every request after initialize.
  _sqlite_catalogue
  _docker_with_running_gateway
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/prettybin"
  cat > "${SANDBOX_DIR}/prettybin/curl" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${CURL_LOG}"
printf '{\n  "jsonrpc": "2.0",\n  "id": 2,\n  "result": {\n    "tools": [\n      {"name": "scratch_execute_sql"}\n    ]\n  }\n}\n'
SH
  chmod +x "${SANDBOX_DIR}/prettybin/curl"
  export PATH="${SANDBOX_DIR}/prettybin:${PATH}"

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "scratch answers"
  grep -q 'MCP-Protocol-Version: 2024-11-05' "${CURL_LOG}"
}

@test "reload: completes and closes the MCP session it opens" {
  # A compliant stateful server refuses tools/list until notifications/initialized
  # arrives, and accumulates sessions unless the client closes them. Both are part
  # of the handshake, not of our convenience.
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_compliant_stateful_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "scratch answers"
  grep -q 'notifications/initialized' "${CURL_LOG}"
  grep -q 'DELETE' "${CURL_LOG}"
}

@test "reload: probes the port the .env configures, not the default" {
  # DATASOURCES_PORT is documented as a compose override, and .env is loaded
  # after the module's shared file is sourced — the URL must therefore be
  # resolved at call time, or the probe and the container disagree.
  _sqlite_catalogue
  printf 'DATASOURCES_PORT=18600\n' > "${SANDBOX_DIR}/.env"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  grep -q '127.0.0.1:18600/mcp/scratch' "${CURL_LOG}"
}

@test "reload: a selected source the gateway still cannot serve is not a success" {
  # The bug scenario: the project selects a source the render dropped. Its
  # manifest exists, so enabling it would fail — say so instead of reporting a
  # clean reload because the other sources answer.
  local drop="${SANDBOX_DIR}/validator-drop-db.py"
  cat > "${drop}" <<'PY'
import json, sys
data = json.load(sys.stdin)
data.pop("db", None)
json.dump(data, sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${drop}"
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } }, "db": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/db.db" } } }'
  _project_config '["scratch", "db"]'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "selected but still unpublishable: db"
  assert_output --partial "reload applied, but not every selected source is served"
}

@test "reload: two published sources are both served, not reported unpublishable" {
  # The real shape: several sources answer and the reload still claims every one
  # of them is unpublishable. The published list is newline-separated, so a
  # space-padded membership test matched nothing and failed the whole reload.
  _catalogue '{ "alpha": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/alpha.db" } }, "beta": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/beta.db" } } }'
  _project_config '["alpha", "beta"]'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "alpha answers"
  assert_output --partial "beta answers"
  assert_output --partial "reload complete; every selected source is served"
  refute_output --partial "selected but still unpublishable"
}

@test "reload: two demanded sidecars are both served, not reported unpublishable" {
  # Same trap on the compose side, in the shape observability actually demands:
  # opensearch AND s3.
  _catalogue '{ "alpha": { "type": "opensearch", "env": {} }, "beta": { "type": "s3", "env": {} } }'
  _project_config '["alpha", "beta"]'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "alpha answers"
  assert_output --partial "beta answers"
  # Sidecars only: the counter is about toolbox sources, so it must not claim 0/0.
  assert_output --partial "no toolbox sources declared"
  refute_output --partial "selected but still unpublishable"
}

@test "reload: warns when another live project's selected source is unpublishable" {
  # The gateway is machine-wide: a source this render drops is dropped for every
  # live project that selected it. That outage is not this project's failure,
  # but it must not be silent either.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["db"]}\n' >"${other}/.devbot.project.jsonc"
  _live_session "${other}"
  _project_config '["scratch"]'
  local drop="${SANDBOX_DIR}/validator-drop-db.py"
  cat > "${drop}" <<'PY'
import json, sys
data = json.load(sys.stdin)
data.pop("db", None)
json.dump(data, sys.stdout)
PY
  export DATASOURCES_VALIDATOR="${drop}"
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } }, "db": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/db.db" } } }'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "another live project selects what is still unpublishable"
  assert_output --partial "db ($(basename "${other}"))"

  rm -rf "${other}"
}

@test "reload: reaps a poller left behind by an older dev-bot" {
  # A detached poller from an older install would rewrite tools.yaml under this
  # render — even after the verification — so the catalogue the command checked
  # may not be the one the gateway is handed.
  _sqlite_catalogue
  _docker_with_running_gateway
  _record_curl
  sleep 60 &
  local sleeper=$!
  mkdir -p "${RUNTIME_DIR}"
  printf '%s\n' "${sleeper}" > "${RUNTIME_DIR}/refresh.pid"

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success

  run kill -0 "${sleeper}"
  assert_failure
  [ ! -f "${RUNTIME_DIR}/refresh.pid" ]

  kill "${sleeper}" 2>/dev/null || true
}

@test "reload: reports a harness manifest that points at a stale endpoint" {
  # A re-render can move a sidecar port, and the harness caches the URL it read
  # at init. Saying "complete" while the toggle would still hit the old port is
  # the same silent failure this command exists to remove.
  _sqlite_catalogue
  _project_config '["scratch"]'
  mkdir -p "${PROJECT_DIR}/.opencode"
  printf '{"datasources-scratch": {"type": "remote", "url": "http://127.0.0.1:1/mcp/scratch", "enabled": false}}\n' \
    > "${PROJECT_DIR}/.opencode/datasources-scratch.mcp.json"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "harness manifests are stale"
  assert_output --partial "devbot reinit"
}

@test "reload: reports a stale Claude manifest too" {
  # claudecode's manifest nests the server under mcpServers; a Claude-only
  # project must not be reported clean while it points at the old endpoint.
  _sqlite_catalogue
  _project_config '["scratch"]' '' 'claudecode'
  mkdir -p "${PROJECT_DIR}/.claude"
  printf '{"mcpServers": {"datasources-scratch": {"type": "http", "url": "http://127.0.0.1:1/mcp/scratch", "enabled": true}}}\n' \
    > "${PROJECT_DIR}/.claude/datasources-scratch.mcp.json"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "harness manifests are stale"
}

@test "reload: a stale manifest of the unselected harness is not reported" {
  # init neither writes nor prunes the unselected harness's manifests, so a
  # leftover from when it was selected must not fail every reload.
  _sqlite_catalogue
  _project_config '["scratch"]' '{}' 'opencode'
  mkdir -p "${PROJECT_DIR}/.claude"
  printf '{"mcpServers": {"datasources-scratch": {"type": "http", "url": "http://127.0.0.1:1/mcp/scratch", "enabled": true}}}\n' \
    > "${PROJECT_DIR}/.claude/datasources-scratch.mcp.json"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  refute_output --partial "manifests are stale"
}

@test "reload: a manifest that matches the rendered endpoint is not stale" {
  _sqlite_catalogue
  _project_config '["scratch"]'
  mkdir -p "${PROJECT_DIR}/.opencode"
  printf '{"datasources-scratch": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/scratch", "enabled": false}}\n' \
    > "${PROJECT_DIR}/.opencode/datasources-scratch.mcp.json"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  refute_output --partial "manifests are stale"
}

@test "reload: a selected datasource the catalogue never declares is not a success" {
  # A typo: init writes the manifest and warns, but no render can ever publish
  # it. "Nothing to serve" must therefore not read as a successful reload.
  _catalogue '{}'
  _project_config '["typo-db"]'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=1 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "selected but still unpublishable: typo-db"
}

@test "reload: a sidecar is accepted on a clean tools/list, with no toolbox tool" {
  # A sidecar's tools come from its own server, never from tools.yaml. Holding
  # it to a `<name>_...` entry would report a healthy sidecar as unavailable.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '["search"]'
  _record_docker
  CURL_LOG="${SANDBOX_DIR}/curl-calls.log"
  mkdir -p "${SANDBOX_DIR}/sidecarbin"
  cat > "${SANDBOX_DIR}/sidecarbin/curl" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${CURL_LOG}"
printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"opensearch_search"}]}}\\n'
SH
  chmod +x "${SANDBOX_DIR}/sidecarbin/curl"
  export PATH="${SANDBOX_DIR}/sidecarbin:${PATH}"

  run env DATASOURCES_PORT=18510 DEV_BOT_MCP_WAIT_TRIES=1 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "search answers"
}

@test "reload: does not verify a sidecar no live session demands" {
  # The compose carries a sidecar for every project that ever selects it, but
  # only a demanded one runs. Verifying the rest would fail every reload on a
  # multi-project machine.
  local other
  other="$(mktemp -d)"
  printf '{"datasources": ["search"]}\n' >"${other}/.devbot.project.jsonc"
  _catalogue_projects '{ "search": { "type": "opensearch", "env": {} } }' "[\"${other}\"]"
  _project_config '[]'
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_success
  refute_output --partial "does not answer"
  refute grep -q '/mcp$' "${CURL_LOG}"

  rm -rf "${other}"
}

@test "reconcile: leaves sidecars alone while another lifecycle run holds the lock" {
  # A stop landing between a reload's sidecar reconciliation and its probe would
  # read as a healthy sidecar being unavailable. Leaving it running is benign —
  # the next boot reconciles — and a session exit must not block.
  _catalogue '{ "search": { "type": "opensearch", "env": {} } }'
  _project_config '[]'
  _docker_reporting_running_sidecars search
  mkdir -p "${RUNTIME_DIR}"
  ( exec 205>"${RUNTIME_DIR}/lifecycle.lock"; flock -x 205; sleep 5 ) &
  sleep 0.3

  # Even with a generous cap in the environment it must not wait: the caller
  # holds the registry lock, and up.sh (lifecycle → registry) would deadlock.
  local started=${SECONDS}
  run env DATASOURCES_LOCK_WAIT=60 bash "${MODULE_DIR}/reconcile.sh"
  local elapsed=$(( SECONDS - started ))
  assert_success
  assert_output --partial "leaving the running sidecars untouched"
  refute grep -q 'stop dev-bot-datasources-search' "${DOCKER_LOG}"
  [ "${elapsed}" -lt 5 ]
}

# ── container e2e (real docker) ───────────────────────────────────────────────

@test "e2e: the oracle accepts a working source and names a bad one" {
  # The only test that runs the pinned image for real. It is what proves the
  # oracle's verdict matches the gateway, which the docker-free unit tests
  # deliberately cannot.
  [[ -n "${REAL_DOCKER}" ]] || skip "docker not available"
  # shellcheck source=./versions.env
  source "${MODULE_DIR}/versions.env"
  "${REAL_DOCKER}" image inspect "${TOOLBOX_IMAGE}:${TOOLBOX_VERSION}" >/dev/null 2>&1 ||
    skip "pinned toolbox image not present"

  # sqlite writes its database under /data, which the canary mounts.
  mkdir -p "${RUNTIME_DIR}/data"

  local catalogue
  catalogue='{"good":{"type":"sqlite","env":{"SQLITE_DATABASE":"/data/good.db"}},"bad":{"type":"mysql","env":{"MYSQL_HOST":"127.0.0.1","MYSQL_PORT":"1","MYSQL_USER":"u","MYSQL_PASSWORD":"p"}}}'
  printf '%s' "${catalogue}" > "${SANDBOX_DIR}/e2e-catalogue.json"

  local out err code
  # ORIGINAL_PATH, so this talks to the REAL docker rather than the stub above.
  out="$(env PATH="${ORIGINAL_PATH}" python3 "${MODULE_DIR}/validate_catalogue.py" \
    --timeout 15 \
    < "${SANDBOX_DIR}/e2e-catalogue.json" 2>"${SANDBOX_DIR}/e2e-stderr")"
  code=$?
  err="$(cat "${SANDBOX_DIR}/e2e-stderr")"

  [ "${code}" -eq 0 ] || fail "validate exited ${code}: ${err}"
  [[ "${out}" == *'"good"'* ]] || fail "accepted set is missing 'good': ${out}"
  [[ "${out}" != *'"bad"'* ]] || fail "the bad source was accepted: ${out}"
  [[ "${err}" == *"datasource 'bad' is not usable"* ]] || fail "no reason for 'bad': ${err}"
}

# ── list membership (pipefail / SIGPIPE) ─────────────────────────────────────

@test "list membership: an early entry in a list past the pipe buffer is found" {
  # The trap this pins: `printf … | grep -q` exits on the match and the writer
  # takes SIGPIPE on its next write, so `pipefail` reports the pipeline failed
  # for a name that IS present — intermittently for short lists, and
  # deterministically for the first entry once the list passes the 64 KiB pipe
  # buffer. That is how the reload flagged a served sidecar as unpublishable.
  local script="${SANDBOX_DIR}/list-membership.sh"
  cat > "${script}" <<SH
set -euo pipefail
source "${MODULE_DIR}/functions.sh"
haystack="\$(seq 1 8000 | sed 's/^/sidecar-/')"
words="\$(tr '\n' ' ' <<< "\${haystack}")"
if printf '%s\n' "\${haystack}" | grep -Fqx sidecar-1; then echo "PIPELINE-OK"; else echo "PIPELINE-FAILED"; fi
_list_has sidecar-1 "\${haystack}" && echo "LINE-FOUND"
_list_has sidecar-99999 "\${haystack}" || echo "LINE-ABSENT"
_list_has_word sidecar-1 "\${words}" && echo "WORD-FOUND"
SH

  run bash "${script}"

  assert_success
  # The fixture must reproduce the trap, or the assertions below pass vacuously.
  assert_output --partial "PIPELINE-FAILED"
  assert_output --partial "LINE-FOUND"
  assert_output --partial "LINE-ABSENT"
  assert_output --partial "WORD-FOUND"
}

