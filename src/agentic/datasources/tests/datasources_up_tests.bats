#!/usr/bin/env bats
# =============================================================================
# src/agentic/datasources/tests/datasources_up_tests.bats
# up.sh and down.sh: the compose lifecycle.
#
# Which sidecars a catalogue demands, the shared gateway, and what down
# leaves behind.
#
# Split from datasources_tests.bats: bats parallelises across files only, so the
# themes are separate files. Fixtures come from datasources_test_helper.
#
# Run from project root:
#   bats src/agentic/datasources/tests/datasources_up_tests.bats
# =============================================================================

load 'datasources_test_helper'

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

