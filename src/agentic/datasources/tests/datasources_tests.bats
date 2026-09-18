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
  # up.sh starts the poller detached; make sure a test never leaks one.
  if [[ -f "${RUNTIME_DIR}/refresh.pid" ]]; then
    kill "$(cat "${RUNTIME_DIR}/refresh.pid")" 2>/dev/null || true
  fi
  rm -rf "${SANDBOX_DIR}" "${PROJECT_DIR}" 2>/dev/null || true
}

# ── fixtures ─────────────────────────────────────────────────────────────────

# The global catalogue. The argument is JSON, so it is passed single-quoted and
# a "${VAR}" reference survives to the config file untouched.
_catalogue() {
  printf '{"datasources": %s}\n' "$1" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

_project_config() {
  local datasources="$1" modules="${2:-}"
  [[ -z "${modules}" ]] && modules='{}'
  printf '{"modules": %s, "datasources": %s}\n' "${modules}" "${datasources}" \
    > "${PROJECT_DIR}/.devbot.project.jsonc"
}

# A datasource that is usable with no environment at all: a literal path, and
# no server to reach.
_sqlite_catalogue() {
  _catalogue '{ "scratch": { "type": "sqlite", "env": { "SQLITE_DATABASE": "/data/scratch.db" } } }'
}

# ── render.sh ────────────────────────────────────────────────────────────────

@test "render: a usable datasource becomes a source, a tool and a toolset" {
  _sqlite_catalogue

  run bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1 datasource(s) usable"

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

@test "render: the compose env list carries references, never literals" {
  # Port 1 keeps the probe off the network: the env list is rendered from the
  # full catalogue regardless of whether the datasource is usable.
  _catalogue '{ "db": { "type": "mysql", "env": { "MYSQL_HOST": "127.0.0.1", "MYSQL_PORT": "1", "MYSQL_USER": "root", "MYSQL_PASSWORD": "${DB_PASS}" } } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_success

  run grep '^    environment:' "${RUNTIME_DIR}/docker-compose.yml"
  assert_success
  assert_output --partial "DB_PASS"
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

@test "poller: an unreadable catalogue leaves the published config alone" {
  # The poller must not turn a transient read failure into an empty render.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  printf 'this is not json\n' > "${SANDBOX_DIR}/.devbot.global.jsonc"

  DATASOURCES_REFRESH_INTERVAL=1 timeout 2 bash "${MODULE_DIR}/poller.sh" \
    >/dev/null 2>&1 || true

  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
}

@test "poller: a due re-validation re-renders with no set change" {
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  # An ancient last-validation makes a re-validation due on every cycle.
  printf '{"sources": {}, "validated_at": 0}\n' > "${RUNTIME_DIR}/quarantine.json"

  DATASOURCES_REFRESH_INTERVAL=1 DATASOURCES_VALIDATE_INTERVAL=1 \
    timeout 2 bash "${MODULE_DIR}/poller.sh" >/dev/null 2>&1 || true

  run grep -c 'revalidating:' "${RUNTIME_DIR}/refresh.log"
  assert_success
}

@test "poller: without state it re-renders only when the set changes" {
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  DATASOURCES_REFRESH_INTERVAL=1 timeout 2 bash "${MODULE_DIR}/poller.sh" >/dev/null 2>&1 || true

  # It did run (a first pass always renders)...
  run grep -c 'usable:' "${RUNTIME_DIR}/refresh.log"
  assert_success
  # ...but nothing asked for a re-validation, so it never re-rendered.
  run grep -c 'revalidating:' "${RUNTIME_DIR}/refresh.log"
  assert_failure
}

@test "render: an all-unusable catalogue keeps the last good config" {
  # Declared datasources that are all unusable is a transient failure, not a
  # removal: publishing the empty render would take every toolset down.
  _sqlite_catalogue
  run bash "${MODULE_DIR}/render.sh"
  assert_success

  local before
  before="$(cat "${CONF_DIR}/tools.yaml")"

  # Declared but env-incomplete (no SQLITE_DATABASE), so nothing is usable.
  _catalogue '{ "scratch": { "type": "sqlite", "env": {} } }'

  run bash "${MODULE_DIR}/render.sh"
  assert_failure
  assert_output --partial "unusable"

  run cat "${CONF_DIR}/tools.yaml"
  assert_output "${before}"
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

@test "init: a selection absent from the catalogue is warned about" {
  _catalogue '{}'
  _project_config '["typo-db"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "not declared"
}

@test "init: nothing is written for a disabled harness" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '{"opencode": false}'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

# ── down.sh ──────────────────────────────────────────────────────────────────

@test "down: no generated compose file is a clean no-op" {
  run bash "${MODULE_DIR}/down.sh"
  assert_success
  assert_output --partial "nothing to stop"
}

# ── up.sh ────────────────────────────────────────────────────────────────────

@test "up: a failed render warns but still starts the gateway" {
  # A render failure (docker down, inconclusive validation) must not abort the
  # boot: a gateway up on the last good config, with the poller retrying, beats
  # no gateway at all.
  _sqlite_catalogue

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
}

# ── container e2e (real docker) ──────────────────────────────────────────────

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
    --state "${RUNTIME_DIR}/e2e-state.json" --timeout 15 \
    < "${SANDBOX_DIR}/e2e-catalogue.json" 2>"${SANDBOX_DIR}/e2e-stderr")"
  code=$?
  err="$(cat "${SANDBOX_DIR}/e2e-stderr")"

  [ "${code}" -eq 0 ] || fail "validate exited ${code}: ${err}"
  [[ "${out}" == *'"good"'* ]] || fail "accepted set is missing 'good': ${out}"
  [[ "${out}" != *'"bad"'* ]] || fail "the bad source was accepted: ${out}"
  [[ "${err}" == *"datasource 'bad' is not usable"* ]] || fail "no reason for 'bad': ${err}"
}
