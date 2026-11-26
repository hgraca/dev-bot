#!/usr/bin/env bats
# =============================================================================
# src/agentic/playwright/tests/playwright_tests.bats
# Tests for the playwright module — the browser MCP, now a machine-wide docker
# compose gateway instead of a per-session `docker run --rm -i`.
#
# WHY the shape changed: one container serves every harness instance over
# streamable-http at 127.0.0.1:18505/mcp. Playwright MCP isolates per client on
# its own — each HTTP client gets a separate browser context, and the workspace
# root it may use is the root that client declares over MCP `roots`, which
# opencode answers with the session's project directory. So the per-project
# context the old stdio launcher got from `-v "$PWD:$PWD" -w "$PWD"` is now
# carried by the protocol instead of by a mount per session.
#
# Verified against the running service (2026-11-26):
#   - streamable-http `initialize` answers 200 on the published port
#   - two clients declaring different roots wrote relative output into those
#     two roots, so root isolation is real
#   - `file:` navigation is blocked by default in BOTH shapes, so the gateway
#     gives up nothing there
#   - the Docker-catalog image `mcp/playwright:latest` is stale (v0.0.76, no
#     roots support): the service must use Microsoft's image
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── Canonical manifest ────────────────────────────────────────────────────────

@test "canonical mcp.json declares playwright as a shared http gateway" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['playwright']
assert m['type'] == 'http', m
assert m['url'] == 'http://127.0.0.1:18505/mcp', m
assert 'command' not in m, m
assert 'env' not in m, m
print('MCP:OK')
"
  assert_success
  assert_output --partial 'MCP:OK'
}

@test "mcp.json ships the server disabled by default (enabled: false)" {
  # Heavy and opt-in: registered wired-but-off, like before the gateway move.
  run python3 -c "
import json
m = json.load(open('${MODULE_DIR}/mcp.json'))['mcp']['playwright']
assert m.get('enabled') is False, m
"
  assert_success
}

@test "no manifest launches docker or npx any more (stdio path retired)" {
  run grep -c 'docker run' "${MODULE_DIR}/mcp.json"
  assert_equal "$output" "0"
  run grep -c 'npx' "${MODULE_DIR}/mcp.json"
  assert_equal "$output" "0"
}

# ── Compose service ───────────────────────────────────────────────────────────

@test "docker-compose.yml declares the gateway on the 18500+ block" {
  local compose="$MODULE_DIR/docker-compose.yml"
  [ -f "$compose" ]
  # Every dev-bot compose file declares the same project name.
  run grep -q 'name: devbot' "$compose"
  assert_success
  # Host-local port mapping only — never exposed off the machine.
  run grep -q '127.0.0.1:18505:18505' "$compose"
  assert_success
}

@test "docker-compose.yml uses Microsoft's image, pinned to the verified build" {
  # mcp/playwright:latest is v0.0.76 (built 2026-06-26) and predates per-client
  # workspace roots — with it every session falls back to one cwd. The pin
  # matters too: the isolation behaviour was verified against v0.0.86, so an
  # unpinned `latest` would silently move it.
  run grep -q 'image: mcr.microsoft.com/playwright/mcp:v0.0.86' "$MODULE_DIR/docker-compose.yml"
  assert_success
  run grep -Eq 'image: (mcp/playwright|mcr.microsoft.com/playwright/mcp)$' "$MODULE_DIR/docker-compose.yml"
  assert_failure
}

@test "a roots-less client still lands inside the mounted tree" {
  # The server falls back to its own cwd when a client declares no MCP roots.
  # The image default (/home/node) is not mounted, so that fallback would write
  # into the container layer and the files would never reach the host. Asserted
  # on the RESOLVED model, so any value that would not mount still fails.
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "compose plugin not installed"

  run env PLAYWRIGHT_ROOT="$HOME" DEV_BOT_ROOT="$PROJECT_ROOT" \
    docker compose -f "$MODULE_DIR/docker-compose.yml" config --format json
  assert_success
  run python3 -c "
import json, sys
svc = json.loads(sys.argv[1])['services']['playwright-mcp']
assert svc.get('working_dir') == '${HOME}', svc.get('working_dir')
mounts = [v for v in svc.get('volumes') or [] if v.get('type') == 'bind']
assert any(m.get('source') == '${HOME}' and m.get('target') == '${HOME}' for m in mounts), mounts
print('WORKDIR:OK')
" "$output"
  assert_success
  assert_output --partial 'WORKDIR:OK'
}

@test "the mount root is mandatory and resolved through the shared helper" {
  # The same compose file is handed to docker by `bin/up.sh main()`, `--is-up`
  # and `bin/down.sh`; a root resolved in only one of them aborts the whole set
  # ("required variable PLAYWRIGHT_ROOT is missing a value") and stops nothing.
  run grep -c 'PLAYWRIGHT_ROOT must be set' "$MODULE_DIR/docker-compose.yml"
  [ "$output" -ge 3 ] || fail "the root must be mandatory in every mount reference"

  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "compose plugin not installed"

  # Bare, compose refuses: that is why every caller resolves first.
  run env -u PLAYWRIGHT_ROOT DEV_BOT_ROOT="$PROJECT_ROOT" \
    docker compose -f "$MODULE_DIR/docker-compose.yml" config --services
  assert_failure

  # With the shared helper, the set resolves — no daemon needed.
  run env -u PLAYWRIGHT_ROOT DEV_BOT_ROOT="$PROJECT_ROOT" bash -c \
    "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_export_playwright_root >/dev/null && docker compose -f '${MODULE_DIR}/docker-compose.yml' config --services"
  assert_success
  assert_output --partial 'playwright-mcp'
}

@test "docker-compose.yml mounts the root at its real path and requires it" {
  local compose="$MODULE_DIR/docker-compose.yml"
  # Same absolute path inside and out: a client's declared root must resolve
  # unchanged, or every file-backed tool call misses. create_host_path: false
  # turns a wrong PLAYWRIGHT_ROOT into a loud failure instead of an empty mount.
  run grep -c 'source: ${PLAYWRIGHT_ROOT:?PLAYWRIGHT_ROOT must be set}' "$compose"
  assert_equal "$output" "1"
  run grep -c 'target: ${PLAYWRIGHT_ROOT:?PLAYWRIGHT_ROOT must be set}' "$compose"
  assert_equal "$output" "1"
  run grep -A3 'source: ${PLAYWRIGHT_ROOT' "$compose"
  assert_line --partial 'create_host_path: false'
}

@test "docker-compose.yml keeps the per-client root guard armed" {
  # --allow-unrestricted-file-access would widen every session to the whole
  # mount; the guard is what makes the declared root a boundary at all. Matched
  # as a YAML list item so the prose mentioning it does not satisfy the check.
  run grep -qE '^[[:space:]]*- --allow-unrestricted-file-access$' "$MODULE_DIR/docker-compose.yml"
  assert_failure
}

@test "docker-compose.yml passes the flags the running service was verified with" {
  local compose="$MODULE_DIR/docker-compose.yml"
  # --isolated: a persistent profile can only be used by one browser instance,
  # and the profile is keyed by workspace root, so two sessions in one repo
  # would collide.
  run grep -q -- '--isolated' "$compose"
  assert_success
  # The allowed-hosts check compares the Host header INCLUDING port; without
  # the published host:port every request 403s.
  run grep -q -- '127.0.0.1:18505' "$compose"
  assert_success
}

@test "the healthcheck closes the session it opens" {
  # The server is stateful: a probe that only initialises leaves one browser
  # context per 30s probe for the container's whole lifetime.
  run grep -c "method: 'DELETE'" "$MODULE_DIR/docker-compose.yml"
  assert_equal "$output" "1"
  run grep -q "mcp-session-id" "$MODULE_DIR/docker-compose.yml"
  assert_success
}

@test "docker-compose.yml follows the gateway house rules" {
  local compose="$MODULE_DIR/docker-compose.yml"
  # Started by `devbot up` and left running — no reboot resurrection.
  run grep -q 'restart: "no"' "$compose"
  assert_success
  # Local/public image reuse: never pull on every up.
  run grep -q 'pull_policy: missing' "$compose"
  assert_success
  # A gateway that stopped answering must read as unhealthy.
  run grep -q 'healthcheck:' "$compose"
  assert_success
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

@test "up.sh waits for the shared gateway" {
  [ -f "$MODULE_DIR/up.sh" ]
  [ -x "$MODULE_DIR/up.sh" ]
  run bash -n "$MODULE_DIR/up.sh"
  assert_success
  run grep -q -- '_devbot_wait_for_mcp_gateway playwright' "$MODULE_DIR/up.sh"
  assert_success
  run grep -q '18505/mcp' "$MODULE_DIR/up.sh"
  assert_success
}

@test "bin/up.sh resolves PLAYWRIGHT_ROOT before compose runs" {
  local bin_up="$PROJECT_ROOT/bin/up.sh"
  run grep -q '^_devbot_resolve_playwright_root() {' "$bin_up"
  assert_success
  # Called before the compose step, or the mount root is never exported.
  # Anchored on the two-space call lines, so the function definitions earlier in
  # the file cannot satisfy the order check.
  run python3 -c "
s = open('${bin_up}').read()
assert s.index('\n  _devbot_resolve_playwright_root\n') < s.index('\n  _docker_up\n'), 'called after compose'
print('ORDER:OK')
"
  assert_success
  assert_output --partial 'ORDER:OK'
}

@test "the stdio-path files are retired" {
  for f in down.sh init.sh install.sh update.sh harness-assets.json versions.env.dist; do
    [ ! -e "$MODULE_DIR/$f" ] || fail "$f should be retired"
  done
}

# ── Reconcile: the container must match the file it was created from ─────────
# Docker fixes every creation-time property and `devbot up` runs compose with
# --no-recreate, so only this step applies an edited compose file. It compares a
# fingerprint (file + mount root) recorded after each successful creation, so a
# changed healthcheck, command, image or mount all reach the container.

_setup_reconcile_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/src/agentic/playwright" "${SANDBOX}/src/_shared" "${SANDBOX}/mockbin"
  cp "${MODULE_DIR}/up.sh" "${SANDBOX}/src/agentic/playwright/up.sh"
  printf 'services:\n  playwright-mcp:\n    image: test\n' \
    > "${SANDBOX}/src/agentic/playwright/docker-compose.yml"

  export CALL_ORDER_FILE="${SANDBOX}/order"
  : > "${CALL_ORDER_FILE}"

  cat > "${SANDBOX}/src/_shared/functions.sh" <<'EOF'
#!/usr/bin/env bash
_info() { true; }
_ok()   { true; }
_skip() { true; }
_warn() { echo "WARN: $*" >&2; }
_error() { echo "ERROR: $*" >&2; return 1; }
_fatal() { echo "FATAL: $*" >&2; return 1; }
_devbot_export_playwright_root() { export PLAYWRIGHT_ROOT="${MOCK_ROOT:-/home/probe}"; }
_devbot_wait_for_mcp_gateway() { printf 'wait\n' >> "${CALL_ORDER_FILE}"; return 0; }
EOF

  cat > "${SANDBOX}/mockbin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CALL_ORDER_FILE}"
case "$1" in
  ps) [[ -n "${MOCK_CID:-}" ]] && echo "${MOCK_CID}"; exit 0 ;;
  inspect) echo "${MOCK_CREATED:-2000-01-01T00:00:00Z}"; exit 0 ;;
  compose) [[ "${MOCK_RECREATE_RC:-0}" == "0" ]] && exit 0 || exit 1 ;;
esac
exit 0
EOF
  chmod +x "${SANDBOX}/mockbin/docker"

  export PATH="${SANDBOX}/mockbin:${PATH}"
  export DEV_BOT_ROOT="${SANDBOX}"
  export MOCK_CID="" MOCK_RECREATE_RC=0
  # Default: the container is older than the file, so drift means recreate.
  export MOCK_CREATED="2000-01-01T00:00:00Z"
}

_run_reconcile() {
  run bash "${SANDBOX}/src/agentic/playwright/up.sh"
}

_recreates() { grep -c 'force-recreate' "${CALL_ORDER_FILE}"; }

@test "reconcile: no container yet means nothing to reconcile" {
  _setup_reconcile_sandbox

  _run_reconcile

  assert_success
  run _recreates
  assert_equal "$output" "0"
}

@test "reconcile: a container created from the current file is left alone" {
  _setup_reconcile_sandbox
  export MOCK_CID=abc
  bash "${SANDBOX}/src/agentic/playwright/up.sh" >/dev/null 2>&1 || true
  # First run records the fingerprint; the second must be a no-op.
  : > "${CALL_ORDER_FILE}"

  _run_reconcile

  assert_success
  run _recreates
  assert_equal "$output" "0"
}

@test "reconcile: a container with no recorded fingerprint is recreated once" {
  # It predates this check (or an older release created it), so the file in
  # force now must be applied exactly once — not on every start.
  _setup_reconcile_sandbox
  export MOCK_CID=abc

  _run_reconcile
  assert_success
  run _recreates
  assert_equal "$output" "1"

  : > "${CALL_ORDER_FILE}"
  _run_reconcile
  assert_success
  run _recreates
  assert_equal "$output" "0"
}

@test "reconcile: an edited compose file recreates the gateway" {
  # This is the case that reaches the container for a changed healthcheck, flag
  # or image — none of which any per-field comparison covers.
  _setup_reconcile_sandbox
  export MOCK_CID=abc
  bash "${SANDBOX}/src/agentic/playwright/up.sh" >/dev/null 2>&1 || true
  printf '# edited\n' >> "${SANDBOX}/src/agentic/playwright/docker-compose.yml"
  : > "${CALL_ORDER_FILE}"

  _run_reconcile

  assert_success
  run _recreates
  assert_equal "$output" "1"
}

@test "reconcile: a changed mount root recreates the gateway" {
  _setup_reconcile_sandbox
  export MOCK_CID=abc
  bash "${SANDBOX}/src/agentic/playwright/up.sh" >/dev/null 2>&1 || true
  : > "${CALL_ORDER_FILE}"

  MOCK_ROOT=/home/other _run_reconcile

  assert_success
  run _recreates
  assert_equal "$output" "1"
}

@test "reconcile: a failed recreate is an error, not a success" {
  # The old container still answers the readiness probe, so reporting success
  # would present a stale configuration as reconciled.
  _setup_reconcile_sandbox
  export MOCK_CID=abc MOCK_RECREATE_RC=1

  _run_reconcile

  assert_failure
  assert_output --partial "still holds the old configuration"
}

# The reconcile sandbox is per test and never shared.
teardown() {
  if [[ -n "${SANDBOX:-}" && -d "${SANDBOX}" ]]; then
    rm -r -- "${SANDBOX}"
  fi
}

@test "the module ships disabled, so no gateway starts by default" {
  # It pulls a browser image and runs a container: a module key absent from the
  # modules map means ENABLED, so the dist config must name it explicitly.
  # JSONC is parsed by the repo's own reader — trailing comments defeat json.loads.
  run python3 "${PROJECT_ROOT}/src/_shared/read_jsonc.py" \
    "${PROJECT_ROOT}/.devbot.global.dist.jsonc" "modules"
  assert_success
  assert_output --partial '"playwright": false'
}

@test "an unusable mount root is refused, including // and a relative path" {
  local lib="${PROJECT_ROOT}/src/_shared/functions.sh"
  for bad in '/' '//' 'relative/path'; do
    run env PLAYWRIGHT_ROOT="${bad}" bash -c "source '${lib}'; _devbot_playwright_root"
    assert_failure
  done
}

@test "reconcile: a container created from the current file is adopted, not recreated" {
  # A clean start has compose create the container moments before this runs; an
  # adoption here avoids recreating it on every fresh start.
  _setup_reconcile_sandbox
  export MOCK_CID=abc
  export MOCK_CREATED="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"))')"

  _run_reconcile

  assert_success
  run _recreates
  assert_equal "$output" "0"
}
