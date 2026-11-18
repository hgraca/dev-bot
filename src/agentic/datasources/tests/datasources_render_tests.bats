#!/usr/bin/env bats
# =============================================================================
# src/agentic/datasources/tests/datasources_render_tests.bats
# render.sh: the availability gate.
#
# Only a usable datasource may reach the gateway config, and the compose env
# list must carry variable NAMES, never literals. Also the install-time
# toolbox image probe.
#
# Split from datasources_tests.bats: bats parallelises across files only, so the
# themes are separate files. Fixtures come from datasources_test_helper.
#
# Run from project root:
#   bats src/agentic/datasources/tests/datasources_render_tests.bats
# =============================================================================

load 'datasources_test_helper'

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

@test "render: a blank .env placeholder does not make an exported value look unset" {
  # The shipped .env.dist lists every credential as `NAME=`. Sourcing that
  # unfilled copy used to blank the value the operator exported in their shell,
  # so a configured datasource was judged env-incomplete, dropped from the
  # gateway, and reported as unset — five such warnings on one real boot where
  # every variable was in .bashrc.
  printf 'MYSQL_PASSWORD=\n' >"${DEV_BOT_ROOT}/.env"
  _catalogue '{ "db": { "type": "mysql", "env": { "MYSQL_HOST": "127.0.0.1", "MYSQL_USER": "root", "MYSQL_PASSWORD": "${MYSQL_PASSWORD}" } } }'

  run env MYSQL_PASSWORD=p bash "${MODULE_DIR}/render.sh"
  assert_success
  assert_output --partial "1/1 toolbox source(s) usable"
  refute_output --partial "not usable"

  run cat "${CONF_DIR}/tools.yaml"
  assert_output --partial "name: db"
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

