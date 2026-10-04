#!/usr/bin/env bats
# =============================================================================
# bin/tests/sync_run_outputs_tests.bats
# Tests for the e2e launchers' host-side helpers in tests/test-project/
# test-lib.sh: reserve_audit_nn() and sync_run_outputs().
#
# The audit report used to be copied back from the run's isolated /app copy at
# launcher exit — too late while an interactive shell kept the launcher alive
# (the report sat in /tmp/devbot-test-* until the human copied it by hand). The
# launchers now bind-mount the fixture's thinking/ dir into the container, so
# the audit writes the report straight onto the fixture — which makes the report
# id a resource parallel runs share. reserve_audit_nn() claims it atomically and
# sync_run_outputs() only files LOGS (never copies, renames, or deletes a report).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  LIB="${REPO_ROOT}/tests/test-project/test-lib.sh"

  SANDBOX="$(mktemp -d)"
  FIXTURE="${SANDBOX}/fixture"
  RUN_DIR="${SANDBOX}/run"
  THINKING="${FIXTURE}/.agents/memory/thinking"

  mkdir -p "${THINKING}" "${FIXTURE}/.agents/logs" "${RUN_DIR}/.agents/logs"

  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}

# ── reserve_audit_nn ──────────────────────────────────────────────────────────

@test "reserve_audit_nn: claims the next free id and creates its placeholder" {
  echo x > "${THINKING}/devbot-audit-05.md"
  run reserve_audit_nn "${THINKING}"
  assert_success
  assert_output "06"
  [[ -f "${THINKING}/devbot-audit-06.md" ]]
}

@test "reserve_audit_nn: successive claims do not collide" {
  run reserve_audit_nn "${THINKING}"
  assert_output "01"
  run reserve_audit_nn "${THINKING}"
  assert_output "02"
}

@test "reserve_audit_nn: ignores probe files that are not numeric reports" {
  : > "${THINKING}/devbot-audit-probe-20260927.md"
  run reserve_audit_nn "${THINKING}"
  assert_output "01"
}

# ── sync_run_outputs ──────────────────────────────────────────────────────────

@test "sync_run_outputs: files logs under the reserved report, never touching reports" {
  echo "old" > "${THINKING}/devbot-audit-66.md"
  echo "new" > "${THINKING}/devbot-audit-67.md"
  echo "log" > "${RUN_DIR}/.agents/logs/memory-index.log"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-67.md"

  assert_success
  assert_output --partial "report written via mount"
  [[ -f "${FIXTURE}/.agents/logs/devbot-audit-67/memory-index.log" ]]
  assert_equal "$(cat "${THINKING}/devbot-audit-66.md")" "old"
  assert_equal "$(cat "${THINKING}/devbot-audit-67.md")" "new"
  [[ ! -f "${THINKING}/devbot-audit-68.md" ]]
}

@test "sync_run_outputs: stages harness logs under the reserved report id" {
  echo "new" > "${THINKING}/devbot-audit-67.md"
  mkdir -p "${RUN_DIR}/.agents/logs/harness"
  echo "mcp" > "${RUN_DIR}/.agents/logs/harness/mcp-logs.jsonl"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-67.md"

  assert_success
  [[ -f "${FIXTURE}/.agents/logs/devbot-audit-67/harness/mcp-logs.jsonl" ]]
}

@test "sync_run_outputs: an unfilled reserved placeholder falls back to a timestamp label" {
  : > "${THINKING}/devbot-audit-07.md" # reserved but never written by the audit
  echo "log" > "${RUN_DIR}/.agents/logs/memory-index.log"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-07.md"

  assert_success
  assert_output --partial "WARN: no devbot-audit report"
  [[ ! -d "${FIXTURE}/.agents/logs/devbot-audit-07" ]]
  assert_equal "$(ls -d "${FIXTURE}"/.agents/logs/oc-* 2>/dev/null | wc -l)" "1"
}

@test "sync_run_outputs: no report and no logs → nothing filed, exits 0" {
  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-01.md"

  assert_success
  assert_equal "$(ls -A "${FIXTURE}/.agents/logs" | wc -l)" "0"
}

# ── launcher wiring ──────────────────────────────────────────────────────────

@test "launchers: mount the fixture thinking/ dir and pass the reserved id" {
  local launcher
  for launcher in test-oc.sh test-cc.sh; do
    run grep -qF '${SCRIPT_DIR}/.agents/memory/thinking:/app/.agents/memory/thinking' \
      "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
    run grep -q 'DEVBOT_AUDIT_NN=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
  done
}

@test "launchers: run a self-contained docker daemon (privileged, no host network)" {
  # The fixture starts its own dockerd inside the container, so the audit's
  # §4/§10 exercise real services without depending on the host daemon, whose
  # gateway ports would collide on the shared host netns.
  local launcher
  for launcher in test-oc.sh test-cc.sh; do
    run grep -qE '^[[:space:]]*--privileged' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
    # Data-root on a volume: nested overlay2 cannot run containers on the
    # image's own overlay backing.
    run grep -qF -- '--mount type=volume,dst=/var/lib/docker' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
    run grep -qE '^[[:space:]]*--network host' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_failure
    # Host-path gateway env no longer flows in: host paths are invalid against
    # the container's own daemon.
    run grep -q 'CODEBASE_MEMORY_ROOT=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_failure
    run grep -q 'CODEBASE_MEMORY_HOST_PROJECT=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_failure
  done
}

@test "inner scripts: start the docker daemon and bring the gateways up" {
  local inner
  for inner in test-oc-inner.sh test-cc-inner.sh; do
    run grep -q 'start_docker_daemon' "${REPO_ROOT}/tests/test-project/${inner}"
    assert_success
    run grep -q 'devbot up' "${REPO_ROOT}/tests/test-project/${inner}"
    assert_success
    # The gateway must be able to see /app (outside $HOME), or the codebase
    # index is silently skipped (audit-77 FAIL-1 / audit-78 FAIL-3).
    run grep -q 'CODEBASE_MEMORY_ROOT=/app' "${REPO_ROOT}/tests/test-project/${inner}"
    assert_success
  done
}

@test "launchers: capture the provisioning stream for the audit to read" {
  local launcher
  for launcher in test-oc.sh test-cc.sh; do
    run grep -qF 'devbot-test-run.log' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
  done
  # And the audit spec must look for that exact path.
  run grep -qF 'devbot-test-run.log' "${REPO_ROOT}/src/tools/devbot-cli/commands/audit.md"
  assert_success
}

@test "inner scripts: grant the opencode permission only when opencode.jsonc exists" {
  # A claudecode-only flow has no opencode.jsonc, so the grant must be guarded
  # rather than called unconditionally — the script otherwise prints a
  # misleading "skip: ... not found" into the provisioning log (audit-82 N1).
  local inner
  for inner in test-cc-inner.sh test-reinit.sh; do
    # The python call is nested under an `if ... opencode.jsonc` guard…
    run grep -qE '^[[:space:]]+python3 .*upsert_opencode_permission\.py' "${REPO_ROOT}/tests/test-project/${inner}"
    assert_success
    run grep -qE '^[[:space:]]*if .*opencode\.jsonc' "${REPO_ROOT}/tests/test-project/${inner}"
    assert_success
  done
  # …but the opencode flow always has the file, so it stays unguarded there.
  run grep -qE '^python3 .*upsert_opencode_permission\.py' "${REPO_ROOT}/tests/test-project/test-oc-inner.sh"
  assert_success
}

@test "audit spec: probe files and cleanup are scoped to the run's report id" {
  # Parallel cc/oc audits share the bind-mounted thinking/ dir; a bare
  # devbot-audit-probe-* cleanup deletes a sibling audit's in-flight probes
  # (audit-82 N5). The spec names and sweeps only its own <NN>-scoped probes.
  local spec="${REPO_ROOT}/src/tools/devbot-cli/commands/audit.md"
  run grep -qF 'devbot-audit-probe-<NN>-*' "$spec"
  assert_success
  run grep -qE '^[[:space:]]*(ls|rm -f)[[:space:]].*devbot-audit-probe-\*' "$spec"
  assert_failure
}

# ── run_dir_create / codebase_gateway_mount ──────────────────────────────────

@test "run_dir_create: builds the run copy under \$DEV_BOT_TEST_RUN_ROOT" {
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}/runs"
  run run_dir_create "${FIXTURE}" "oc"
  assert_success
  local created="$output"
  [[ -d "${created}" ]]
  assert_equal "${created%/*}" "${DEV_BOT_TEST_RUN_ROOT}"
  run_dir_destroy "${created}"
  [[ ! -d "${created}" ]]
}

@test "run_dir_destroy: refuses to remove a path outside the run root" {
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}/runs"
  mkdir -p "${SANDBOX}/keep"
  run_dir_destroy "${SANDBOX}/keep"
  [[ -d "${SANDBOX}/keep" ]]
}

@test "codebase_gateway_mount: reads the gateway's bind source" {
  local stub="${SANDBOX}/bin"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\necho "/host/root"\n' > "${stub}/docker"
  chmod +x "${stub}/docker"
  run env PATH="${stub}:${PATH}" bash -c "source '${LIB}'; codebase_gateway_mount"
  assert_success
  assert_output "/host/root"
}

@test "codebase_gateway_mount: falls back to \$HOME when the gateway is absent" {
  local stub="${SANDBOX}/bin2"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${stub}/docker"
  chmod +x "${stub}/docker"
  run env PATH="${stub}:${PATH}" HOME="/fallback/home" bash -c "source '${LIB}'; codebase_gateway_mount"
  assert_success
  assert_output "/fallback/home"
}

# ── codebase_memory_prune_run ─────────────────────────────────────────────────
# A run's index entry outlives run_dir_destroy on the shared gateway volume, so
# teardown prunes it over MCP (audit-73 §4 / audit-74 §4). These tests drive the
# helper against a stub gateway speaking the same streamable-http handshake.

_stub_gateway() {
  # _stub_gateway <prefix> <port> <deleted-log> — writes the stub, runs it, prints pid.
  cat > "${SANDBOX}/stub-gateway.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

prefix, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]
call_status = int(sys.argv[4]) if len(sys.argv) > 4 else 200
delete_refused = len(sys.argv) > 5 and sys.argv[5] == "refused"
SID = "stub-session"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Mcp-Session-Id", SID)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        message = json.loads(self.rfile.read(length) or b"{}")
        method = message.get("method")
        if method == "initialize":
            self._send(200, {"jsonrpc": "2.0", "id": message.get("id"),
                             "result": {"protocolVersion": "2024-11-05",
                                        "capabilities": {},
                                        "serverInfo": {"name": "stub", "version": "1"}}})
        elif method == "notifications/initialized":
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif method == "tools/call":
            if call_status != 200:
                body = b"stub failure"
                self.send_response(call_status)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            name = message["params"]["name"]
            if name == "list_projects":
                text = json.dumps({"projects": [
                    {"name": "mine-src", "root_path": prefix + "/src"},
                    {"name": "other-src", "root_path": "/elsewhere/src"},
                ], "total": 2, "offset": 0, "limit": 100,
                    "returned": 2, "has_more": False})
            elif name == "delete_project":
                if delete_refused:
                    text = json.dumps({"deleted": False})
                else:
                    with open(log, "a") as handle:
                        handle.write(message["params"]["arguments"]["project"] + "\n")
                    text = json.dumps({"deleted": True})
            else:
                text = "{}"
            self._send(200, {"jsonrpc": "2.0", "id": message.get("id"),
                             "result": {"content": [{"type": "text", "text": text}],
                                        "isError": False}})
        else:
            self._send(200, {"jsonrpc": "2.0", "id": message.get("id"), "result": {}})

    def do_DELETE(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

  # stdout/stderr to a file: a background server inheriting the test's captured
  # stdout would hold that pipe open and hang `run` until BATS gave up.
  python3 "${SANDBOX}/stub-gateway.py" "$1" "$2" "$3" "${4:-200}" "${5:-}" \
    >"${SANDBOX}/stub-gateway.out" 2>&1 &
  echo $!
}

_free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

_wait_for_port() {
  local port="$1" i
  for i in $(seq 1 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', ${port}), 0.2).close()" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "codebase_memory_prune_run: deletes only the entries under the run prefix" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}"
  local prefix="${SANDBOX}/devbot-test-oc.ABC" log="${SANDBOX}/deleted.txt"
  : >"$log"
  local port pid
  port="$(_free_port)"
  pid="$(_stub_gateway "$prefix" "$port" "$log")"
  _wait_for_port "$port" || {
    kill "$pid" 2>/dev/null || true
    skip "stub gateway did not start"
  }

  run env CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:${port}/mcp" \
    bash -c "source '${LIB}'; codebase_memory_prune_run '${prefix}'"
  kill "$pid" 2>/dev/null || true

  assert_success
  assert_output --partial "pruned 1 stale project"
  assert_equal "$(cat "$log")" "mine-src"
}

@test "codebase_memory_prune_run: is a quiet no-op when the gateway is down" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}"
  run env CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:1/mcp" \
    bash -c "source '${LIB}'; codebase_memory_prune_run '${SANDBOX}/devbot-test-oc.DEAD'"
  assert_success
  refute_output --partial "pruned"
}

@test "codebase_memory_prune_run: a mid-walk gateway error stays quiet" {
  # Only the pre-initialize path (gateway down) was covered before: a transport
  # error AFTER a successful initialize escaped as a Python traceback (exit 0
  # only via the shell's `|| true`) — a false failure signal for a best-effort
  # cleanup step.
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}"
  local prefix="${SANDBOX}/devbot-test-oc.HALF" log="${SANDBOX}/deleted.txt"
  : >"$log"
  local port pid
  port="$(_free_port)"
  pid="$(_stub_gateway "$prefix" "$port" "$log" 500)"
  _wait_for_port "$port" || {
    kill "$pid" 2>/dev/null || true
    skip "stub gateway did not start"
  }

  run env CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:${port}/mcp" \
    bash -c "source '${LIB}'; codebase_memory_prune_run '${prefix}'"
  kill "$pid" 2>/dev/null || true

  assert_success
  refute_output --partial "Traceback"
  assert_equal "$(cat "$log")" ""
}

@test "codebase_memory_prune_run: refuses a prefix outside the run root" {
  # The delete is destructive on shared gateway state, so the helper mirrors
  # run_dir_destroy's guard. The stub WOULD report and delete a project for this
  # prefix — the guard must stop the helper before it ever connects.
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}/runs"
  local log="${SANDBOX}/deleted.txt"
  : >"$log"
  local port pid
  port="$(_free_port)"
  pid="$(_stub_gateway "${SANDBOX}" "$port" "$log")"
  _wait_for_port "$port" || {
    kill "$pid" 2>/dev/null || true
    skip "stub gateway did not start"
  }

  run env CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:${port}/mcp" \
    bash -c "source '${LIB}'; codebase_memory_prune_run '${SANDBOX}'"
  kill "$pid" 2>/dev/null || true

  assert_success
  refute_output --partial "pruned"
  assert_equal "$(cat "$log")" ""
}

@test "codebase_memory_prune_run: does not count a refused delete as pruned" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required"
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}"
  local prefix="${SANDBOX}/devbot-test-oc.REF" log="${SANDBOX}/deleted.txt"
  : >"$log"
  local port pid
  port="$(_free_port)"
  pid="$(_stub_gateway "$prefix" "$port" "$log" 200 refused)"
  _wait_for_port "$port" || {
    kill "$pid" 2>/dev/null || true
    skip "stub gateway did not start"
  }

  run env CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:${port}/mcp" \
    bash -c "source '${LIB}'; codebase_memory_prune_run '${prefix}'"
  kill "$pid" 2>/dev/null || true

  assert_success
  refute_output --partial "pruned"
}
