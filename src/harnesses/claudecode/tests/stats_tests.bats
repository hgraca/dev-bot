#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/stats_tests.bats
# Tests for the claudecode `devbot stats` adapter.
#
# Claude Code has no stats command, so the adapter parses the session
# transcripts under <projects>/<slug>/**/*.jsonl. Claude Code writes one JSONL
# line per content block of an assistant response, repeating the message id and
# usage on every line — so the adapter groups lines by message id, takes the
# usage once, and splits it across that message's tool_use blocks. It also
# includes subagent transcripts, classifies mcp__<server>__<tool> names, and
# reports cost as null (transcripts carry no cost data).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  SANDBOX="$(mktemp -d)"
  PROJECT_DIR="${SANDBOX}/project"
  OTHER_DIR="${SANDBOX}/other"
  PROJECTS_DIR="${SANDBOX}/projects"
  mkdir -p "${PROJECT_DIR}" "${OTHER_DIR}" "${PROJECTS_DIR}"
  export CLAUDE_PROJECTS_DIR="${PROJECTS_DIR}"

  # Claude Code slug = cwd with '/' replaced by '-'.
  local slug other_slug
  slug="$(printf '%s' "${PROJECT_DIR}" | tr '/' '-')"
  other_slug="$(printf '%s' "${OTHER_DIR}" | tr '/' '-')"
  mkdir -p "${PROJECTS_DIR}/${slug}/sess-1/subagents" "${PROJECTS_DIR}/${other_slug}"

  python3 - "${PROJECTS_DIR}/${slug}/main.jsonl" \
            "${PROJECTS_DIR}/${slug}/sess-1/subagents/sub.jsonl" \
            "${PROJECTS_DIR}/${other_slug}/main.jsonl" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)

def usage(i, o, cr=0, cc=0):
    return {"input_tokens": i, "output_tokens": o,
            "cache_read_input_tokens": cr, "cache_creation_input_tokens": cc}

def line(msg_id, ts, usg, tool=None):
    content = [{"type": "tool_use", "name": tool}] if tool else [{"type": "text", "text": "hi"}]
    return json.dumps({
        "type": "assistant",
        "timestamp": ts.isoformat().replace("+00:00", "Z"),
        "message": {"id": msg_id, "usage": usg, "content": content},
    })

main = [
    # Single-tool message: 115 tokens to Read.
    line("m-read", now - timedelta(hours=1), usage(10, 5, cr=100), "Read"),
    # One message split across two lines (parallel tool calls): 100 tokens
    # total, split 50/50 across foo and bar — NOT 100 each.
    line("m-parallel", now - timedelta(minutes=30), usage(40, 60), "mcp__demo__foo"),
    line("m-parallel", now - timedelta(minutes=30), usage(40, 60), "mcp__demo__bar"),
    # Text-only message: must not count.
    line("m-text", now, usage(99, 99)),
    # Old message, outside a 30-day window.
    line("m-old", now - timedelta(days=40), usage(7, 7), "mcp__demo__old"),
]
with open(sys.argv[1], "w") as fh:
    fh.write("\n".join(main) + "\n")

# Subagent transcript: its tool calls must be included.
sub = [line("m-sub", now - timedelta(minutes=20), usage(30, 70), "mcp__demo__sub")]
with open(sys.argv[2], "w") as fh:
    fh.write("\n".join(sub) + "\n")

# Another project: excluded unless --all.
other = [line("m-other", now - timedelta(hours=1), usage(4, 4), "Bash")]
with open(sys.argv[3], "w") as fh:
    fh.write("\n".join(other) + "\n")
PY
}

teardown() {
  rm -rf "${SANDBOX}"
}

run_adapter() {
  ( cd "${PROJECT_DIR}" && bash "${MODULE_DIR}/stats.sh" "$@" )
}

json() {
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print(eval(sys.argv[1]))
" "$1"
}

# ── Contract ──────────────────────────────────────────────────────────────────

@test "adapter emits canonical JSON with harness and null cost_kind" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]
  assert_output --partial '"schema": 1'
  echo "${output}" | json "data['harness']" | grep -Fqx "claudecode"
  echo "${output}" | json "data['cost_kind']" | grep -Fqx "None"
}

@test "adapter attributes message tokens once and splits them across the message's tools" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]

  echo "${output}" | json "[(t['name'], t['count'], t['tokens']) for t in data['tools'] if t['name']=='Read'][0]" | grep -Fqx "('Read', 1, 115)"
  # The parallel message (100 tokens) is split 50/50, not 100 each.
  echo "${output}" | json "[(t['name'], t['count'], t['tokens']) for t in data['tools'] if t['name']=='mcp__demo__foo'][0]" | grep -Fqx "('mcp__demo__foo', 1, 50)"
  echo "${output}" | json "[(t['name'], t['count'], t['tokens']) for t in data['tools'] if t['name']=='mcp__demo__bar'][0]" | grep -Fqx "('mcp__demo__bar', 1, 50)"
  # text-only message must not create a tool
  echo "${output}" | json "len([t for t in data['tools'] if t['count']==99])" | grep -Fqx "0"
}

@test "adapter includes subagent transcripts" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]
  echo "${output}" | json "[(t['name'], t['count'], t['tokens']) for t in data['tools'] if t['name']=='mcp__demo__sub'][0]" | grep -Fqx "('mcp__demo__sub', 1, 100)"
}

@test "adapter aggregates mcp__<server>__<tool> names by server" {
  run run_adapter --days=30
  [ "${status}" -eq 0 ]

  echo "${output}" | json "[(s['server'], s['count']) for s in data['mcp_servers']]" | grep -Fqx "[('demo', 3)]"
  echo "${output}" | json "sorted((t['name'], t['count'], t['tokens']) for s in data['mcp_servers'] for t in s['tools'])" | grep -Fqx "[('bar', 1, 50), ('foo', 1, 50), ('sub', 1, 100)]"
  # native tools are never MCP servers
  echo "${output}" | json "len([s for s in data['mcp_servers'] if s['server']=='Read'])" | grep -Fqx "0"
}

@test "adapter excludes other projects by default and includes them with --all" {
  run run_adapter --days=30
  refute_output --partial '"Bash"'

  run run_adapter --days=30 --all
  [ "${status}" -eq 0 ]
  assert_output --partial '"Bash"'
}

@test "adapter excludes messages older than the day window" {
  run run_adapter --days=30
  refute_output --partial '"mcp__demo__old"'

  run run_adapter --days=60
  assert_output --partial '"mcp__demo__old"'
}

@test "adapter reports an empty window when the project has no transcripts" {
  mkdir -p "${SANDBOX}/empty"
  run bash -c "cd '${SANDBOX}/empty' && bash '${MODULE_DIR}/stats.sh' --days=30"
  [ "${status}" -eq 0 ]
  echo "${output}" | json "data['tools']" | grep -Fqx "[]"
}

@test "adapter aggregates Bash/Skill/Grep/Glob arguments" {
  local dir="${SANDBOX}/argproj" projects="${SANDBOX}/argprojects"
  mkdir -p "${dir}" "${projects}"
  local slug
  slug="$(printf '%s' "${dir}" | tr '/' '-')"
  mkdir -p "${projects}/${slug}"

  python3 - "${projects}/${slug}/s.jsonl" <<'PY'
import json, sys
from datetime import datetime, timezone

now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def line(mid, tool, inp):
    return json.dumps({"type": "assistant", "timestamp": now,
                       "message": {"id": mid, "usage": {"input_tokens": 1, "output_tokens": 1},
                                   "content": [{"type": "tool_use", "name": tool, "input": inp}]}})

rows = [
    line("a", "Bash", {"command": "cd /x && make test"}),
    line("b", "Skill", {"skill": "devbot:make-plan"}),
    line("c", "Grep", {"pattern": "foo"}),
    line("d", "Glob", {"pattern": "**/*.bats"}),
]
with open(sys.argv[1], "w") as fh:
    fh.write("\n".join(rows) + "\n")
PY

  export CLAUDE_PROJECTS_DIR="${projects}"
  run bash -c "cd '${dir}' && bash '${MODULE_DIR}/stats.sh' --days=30"
  [ "${status}" -eq 0 ]
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['bash']]" | grep -Fqx "[('make test', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['skill']]" | grep -Fqx "[('devbot:make-plan', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['grep']]" | grep -Fqx "[('foo', 1)]"
  echo "${output}" | json "[(e['value'], e['count']) for e in data['tool_arguments']['glob']]" | grep -Fqx "[('**/*.bats', 1)]"
}
