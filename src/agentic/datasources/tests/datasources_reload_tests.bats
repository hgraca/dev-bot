#!/usr/bin/env bats
# =============================================================================
# src/agentic/datasources/tests/datasources_reload_tests.bats
# reload.sh: reconcile without a restart.
#
# Picking up a catalogue edit, the session gate, and the container e2e that
# needs a real docker daemon.
#
# Split from datasources_tests.bats: bats parallelises across files only, so the
# themes are separate files. Fixtures come from datasources_test_helper.
#
# Run from project root:
#   bats src/agentic/datasources/tests/datasources_reload_tests.bats
# =============================================================================

load 'datasources_test_helper'
load '../../../_shared/tests/lib/pins.bash'

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

@test "reload: reports a published manifest that points at a stale endpoint" {
  # A re-render can move a sidecar port, and init published the old URL for the
  # harness to copy. A reload cannot rewrite what was already published, so it
  # must not claim success while the toggle would still hit the old port.
  _sqlite_catalogue
  _project_config '["scratch"]'
  mkdir -p "${PROJECT_DIR}/.agents/mcp-runtime"
  printf '{"mcp": {"ds-scratch": {"type": "http", "url": "http://127.0.0.1:1/mcp/scratch", "wire_disabled": true}}}\n' \
    > "${PROJECT_DIR}/.agents/mcp-runtime/datasources-scratch.json"
  _docker_with_running_gateway
  _record_curl

  run env DATASOURCES_PORT=18510 DATASOURCES_RELOAD_WAIT=0 DATASOURCES_RELOAD_PROBE_TRIES=1 \
    bash "${MODULE_DIR}/reload.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "harness manifests are stale"
  assert_output --partial "devbot reinit"
}

@test "reload: a published manifest that matches the rendered endpoint is not stale" {
  _sqlite_catalogue
  _project_config '["scratch"]'
  mkdir -p "${PROJECT_DIR}/.agents/mcp-runtime"
  printf '{"mcp": {"ds-scratch": {"type": "http", "url": "http://127.0.0.1:18510/mcp/scratch", "wire_disabled": true}}}\n' \
    > "${PROJECT_DIR}/.agents/mcp-runtime/datasources-scratch.json"
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
  # The pin is machine-local (gitignored); the shipped default is the fallback.
  # shellcheck source=/dev/null
  source "$(pins_file "${MODULE_DIR}")"
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

