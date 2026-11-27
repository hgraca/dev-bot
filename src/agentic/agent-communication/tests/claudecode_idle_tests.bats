#!/usr/bin/env bats
# src/agentic/agent-communication/tests/claudecode_idle_tests.bats
# The Claude Code Stop hook path: the transcript's last assistant turn is
# validated and its marker is published to herdr as a display-only token.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  SCRIPT="${MODULE_DIR}/tools/claudecode-idle.sh"

  SANDBOX="$(mktemp -d)"
  HERDR_CALLS="${SANDBOX}/herdr.calls"
  : >"${HERDR_CALLS}"

  cat >"${SANDBOX}/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${HERDR_CALLS}"
exit 0
EOF
  chmod +x "${SANDBOX}/herdr"

  export HERDR_ENV=1
  export HERDR_PANE_ID=w1:p1
  export HERDR_BIN_PATH="${SANDBOX}/herdr"
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

# _transcript <name> <assistant-text>: one user turn, then an assistant turn
# carrying that text, as Claude Code writes its JSONL.
_transcript() {
  local path="${SANDBOX}/$1.jsonl"
  python3 - "$path" "$2" <<'PY'
import json, sys
path, text = sys.argv[1], sys.argv[2]
with open(path, "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "go"}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "text", "text": "done"},
        {"type": "tool_use", "name": "Bash", "input": {"command": "true"}},
        {"type": "text", "text": text},
    ]}}) + "\n")
print(path)
PY
}

@test "publishes the marker the last assistant turn ends on" {
  t="$(_transcript marker '[PARTIAL]')"
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=PARTIAL"
  assert_output --partial "pane report-metadata w1:p1"
}

@test "clears the token when the turn does not end on a marker" {
  t="$(_transcript midbody 'Here is why [PARTIAL] applies.')"
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot="
  refute_output --partial "devbot=PARTIAL"
}

@test "does nothing without a transcript (the opencode hosts)" {
  run bash "${SCRIPT}" --transcript ""
  assert_success
  [ ! -s "${HERDR_CALLS}" ]
}

@test "does nothing outside a herdr pane" {
  t="$(_transcript outside '[FINISHED]')"
  unset HERDR_ENV
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  [ ! -s "${HERDR_CALLS}" ]
}

@test "does nothing when the last turn is not an assistant turn" {
  t="${SANDBOX}/user-only.jsonl"
  python3 - "$t" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "[FINISHED]"}]}}) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  [ ! -s "${HERDR_CALLS}" ]
}

@test "publishes the marker from an earlier record of the last turn" {
  # Claude Code writes one record per content block, repeating the message id.
  t="${SANDBOX}/grouped.jsonl"
  python3 - "$t" <<'PY'
import json, sys
rec = lambda block: {"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [block]}}
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": "go"}]}}) + "\n")
    f.write(json.dumps(rec({"type": "text", "text": "Done."})) + "\n")
    f.write(json.dumps(rec({"type": "tool_use", "name": "Bash", "input": {"command": "true"}})) + "\n")
    f.write(json.dumps(rec({"type": "text", "text": "[FINISHED]"})) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=FINISHED"
}

@test "clears a [WAITING_FOR_PTY] that started no wait" {
  t="$(_transcript waiting '[WAITING_FOR_PTY]')"
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot="
  refute_output --partial "devbot=WAITING_FOR_PTY"
}

@test "publishes [WAITING_FOR_PTY] backed by a background Bash" {
  t="${SANDBOX}/waiting-backed.jsonl"
  python3 - "$t" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [
        {"type": "text", "text": "Spawned it."},
        {"type": "tool_use", "name": "Bash", "input": {"command": "make test", "run_in_background": True}},
        {"type": "text", "text": "[WAITING_FOR_PTY]"},
    ]}}) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=WAITING_FOR_PTY"
}

@test "finds a wait that started before a very large turn" {
  # The background tool sits outside the 256 KiB window; widening must find it
  # or the wait marker is cleared as unbacked.
  t="${SANDBOX}/large-turn.jsonl"
  python3 - "$t" <<'PY'
import json, sys
# One record per content block, as Claude Code writes them.
def rec(block):
    return {"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [block]}}
with open(sys.argv[1], "w") as f:
    for block in (
        {"type": "tool_use", "name": "Bash", "input": {"command": "make test", "run_in_background": True}},
        {"type": "text", "text": "working" * 40000},
        {"type": "text", "text": "[WAITING_FOR_PTY]"},
    ):
        f.write(json.dumps(rec(block)) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=WAITING_FOR_PTY"
}

@test "finds the turn behind a long run of other records" {
  t="${SANDBOX}/long-prefix.jsonl"
  python3 - "$t" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(4000):
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
            {"type": "text", "text": "x" * 200}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [
        {"type": "text", "text": "[FINISHED]"}]}}) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=FINISHED"
}

@test "a subagent transcript never publishes" {
  # A delegated agent shares the pane: its Stop hook must not claim the turn.
  mkdir -p "${SANDBOX}/proj/subagents"
  t="$(_transcript subagent '[FINISHED]')"
  mv "${t}" "${SANDBOX}/proj/subagents/agent-1.jsonl"
  run bash "${SCRIPT}" --transcript "${SANDBOX}/proj/subagents/agent-1.jsonl"
  assert_success
  [ ! -s "${HERDR_CALLS}" ]
}

@test "publishes from a transcript outside a subagents directory" {
  mkdir -p "${SANDBOX}/proj"
  t="$(_transcript top '[FINISHED]')"
  mv "${t}" "${SANDBOX}/proj/session.jsonl"
  run bash "${SCRIPT}" --transcript "${SANDBOX}/proj/session.jsonl"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=FINISHED"
}

@test "an id-less assistant turn is read from the tail, never widened for" {
  # Nothing identifies a wider turn, so the scan must settle on what it has
  # instead of re-reading the file on every Stop.
  t="${SANDBOX}/idless.jsonl"
  python3 - "$t" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for _ in range(4000):
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
            {"type": "text", "text": "x" * 200}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "text", "text": "[FINISHED]"}]}}) + "\n")
PY
  run bash "${SCRIPT}" --transcript "${t}"
  assert_success
  run cat "${HERDR_CALLS}"
  assert_output --partial "--token devbot=FINISHED"
}

@test "a turn larger than the window cap is not published, and the scan ends" {
  # Accepting a partial turn would clear a valid wait; spinning would hang the
  # Stop hook. The cap must end the scan with nothing published.
  t="${SANDBOX}/oversized.jsonl"
  python3 - "$t" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [
        {"type": "tool_use", "name": "Bash", "input": {"command": "true", "run_in_background": True}},
        {"type": "text", "text": "x" * (9 * 1024 * 1024)},
        {"type": "text", "text": "[WAITING_FOR_PTY]"},
    ]}}) + "\n")
PY
  run timeout 20 bash "${SCRIPT}" --transcript "${t}"
  assert_success
  [ ! -s "${HERDR_CALLS}" ]
}
