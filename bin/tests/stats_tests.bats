#!/usr/bin/env bats
# =============================================================================
# bin/tests/stats_tests.bats
# Tests for `devbot stats` — the harness-agnostic tool + MCP usage report.
#
# Validates that:
#   - The CLI parses --days/--all/--harness and rejects bad input
#   - The harness adapter is discovered, invoked with the right args, and its
#     canonical JSON is validated before rendering
#   - A missing adapter fails with a FATAL and a non-zero exit
#   - The Markdown renderer adapts its columns (Cost/Tokens appear only when
#     the adapter supplies them)
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  # Sandbox = a throwaway "project" whose config points at the harness under
  # test. Adapter dir = a throwaway src/harnesses tree with a fake adapter.
  SANDBOX="$(mktemp -d)"
  ADAPTER_DIR="$(mktemp -d)"
  export DEV_BOT_STATS_HARNESS_DIR="${ADAPTER_DIR}"
  export FAKE_ARGS_FILE="${SANDBOX}/adapter-args.txt"
}

teardown() {
  rm -rf "${SANDBOX}" "${ADAPTER_DIR}"
}

# Install a fake harness adapter that records its argv and echoes $1 (a JSON
# fixture path). $1 = harness name, $2 = fixture JSON path.
install_fake_adapter() {
  local harness="$1" fixture="$2"
  mkdir -p "${ADAPTER_DIR}/${harness}"
  cat > "${ADAPTER_DIR}/${harness}/stats.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${FAKE_ARGS_FILE}"
cat "${fixture}"
EOF
  chmod +x "${ADAPTER_DIR}/${harness}/stats.sh"
}

# A project whose configured harness is $1.
make_project() {
  local harness="$1"
  printf '{"harness":"%s"}\n' "${harness}" > "${SANDBOX}/.devbot.project.jsonc"
}

# Validate a markdown table block: header, separator, aligned pipes.
# $1 = expected column count. Reads the table from stdin.
assert_well_formed_table() {
  python3 -c "
import sys, re
expected = int(sys.argv[1])
lines = [l for l in sys.stdin.read().splitlines() if l.strip()]
assert len(lines) >= 3, f'expected header+separator+row, got {len(lines)}'
for i, l in enumerate(lines):
    n = l.count('|')
    assert n == expected + 1, f'row {i}: expected {expected+1} pipes, got {n}: {l!r}'
assert re.fullmatch(r'[| :\-]+', lines[1]), f'bad separator row: {lines[1]!r}'
positions = {tuple(i for i, c in enumerate(l) if c == '|') for l in lines}
assert len(positions) == 1, f'misaligned pipes: {positions}'
" "$1"
}

FIXTURE_JSON='{
  "schema": 1,
  "harness": "opencode",
  "days": 7,
  "scope": "current",
  "scope_label": "/tmp/proj",
  "generated_at": "2026-09-10T16:40:00Z",
  "cost_kind": "estimated",
  "tools": [
    {"name": "bash", "count": 100, "tokens": 5000, "cost": 1.5},
    {"name": "read", "count": 60, "tokens": 3000, "cost": 0.9},
    {"name": "devbot-tools_search-memories", "count": 40, "tokens": 2000, "cost": 0.4}
  ],
  "mcp_servers": [
    {"server": "devbot-tools", "count": 40, "tokens": 2000, "cost": 0.4,
     "tools": [{"name": "search-memories", "count": 40, "tokens": 2000, "cost": 0.4}]}
  ]
}'

write_fixture() {
  printf '%s\n' "${FIXTURE_JSON}" > "${SANDBOX}/fixture.json"
}

# A one-row tools-grades.csv whose single row belongs to $1 (a project label).
# The label deliberately never matches the sandbox's own project name, so the
# "current scope" tests can rely on the row being filtered out.
write_grades_csv() {
  cat > "${SANDBOX}/tools-grades.csv" <<CSV
session_id,datetime,project,notes,skill:devbot:makefile
s-01,2026-09-18 12:00:00,$1,"makefile (2): the Makefile covered it.",2
CSV
}

# ── CLI surface ───────────────────────────────────────────────────────────────

@test "devbot stats --help prints usage" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --help
  [ "${status}" -eq 0 ]
  assert_output --partial "Usage: devbot stats"
  assert_output --partial "--days"
  assert_output --partial "--all"
  assert_output --partial "--harness"
}

@test "devbot stats rejects an unknown argument" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --bogus
  [ "${status}" -ne 0 ]
  assert_output --partial "Unknown argument"
}

@test "devbot stats rejects a non-numeric --days" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --days=abc
  [ "${status}" -ne 0 ]
  assert_output --partial "Invalid --days"
}

@test "devbot stats fails with a FATAL when the harness has no adapter" {
  # claudecode is a valid harness, but no adapter is installed in the override
  # dir, so the parent must fail clearly instead of guessing.
  make_project "claudecode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats"
  [ "${status}" -ne 0 ]
  assert_output --partial "FATAL"
  assert_output --partial "claudecode"
}

@test "devbot stats defaults to every project" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --days=7"
  [ "${status}" -eq 0 ]

  run cat "${FAKE_ARGS_FILE}"
  assert_line "--days"
  assert_line "7"
  assert_line "--all"
  refute_line "--project"
}

@test "devbot stats passes --project to the harness adapter" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  local resolved
  resolved="$(cd "${SANDBOX}" && pwd)"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --project='${SANDBOX}'"
  [ "${status}" -eq 0 ]

  run cat "${FAKE_ARGS_FILE}"
  assert_line "--project"
  assert_line "${resolved}"
  refute_line "--all"
}

@test "devbot stats rejects --project together with --all" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --project=/tmp --all
  [ "${status}" -ne 0 ]
  assert_output --partial "mutually exclusive"
}

# ── Adapter invocation + rendering ────────────────────────────────────────────

@test "devbot stats passes --days and --all to the harness adapter" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --days=7 --all"
  [ "${status}" -eq 0 ]

  run cat "${FAKE_ARGS_FILE}"
  assert_line "--days"
  assert_line "7"
  assert_line "--all"
}

@test "devbot stats renders a markdown report from the adapter JSON" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --days=7"
  [ "${status}" -eq 0 ]

  assert_output --partial "# DevBot Tool Usage"
  assert_output --partial "opencode"
  assert_output --partial "## Tool Usage"
  assert_output --partial "| bash"
  assert_output --partial "## MCP Server Usage"
  assert_output --partial "| devbot-tools"
  assert_output --partial "search-memories (40)"
  assert_output --partial "Cost (est.)"
}

@test "devbot stats rejects adapter output that is not JSON" {
  mkdir -p "${ADAPTER_DIR}/opencode"
  printf '#!/usr/bin/env bash\n echo "not json"\n' > "${ADAPTER_DIR}/opencode/stats.sh"
  chmod +x "${ADAPTER_DIR}/opencode/stats.sh"
  make_project "opencode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats"
  [ "${status}" -ne 0 ]
  assert_output --partial "invalid JSON"
}

# ── Renderer column adaptation ────────────────────────────────────────────────

@test "renderer emits well-formed tables" {
  write_fixture
  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/fixture.json"
  [ "${status}" -eq 0 ]

  # extract the Tool Usage table (from the "| #" header to the next blank line)
  echo "${output}" | python3 -c "
import sys
lines = sys.stdin.read().splitlines()
start = next(i for i, l in enumerate(lines) if '| Tool' in l and 'Calls' in l)
table = []
for l in lines[start:]:
    if not l.strip():
        break
    table.append(l)
print('\n'.join(table))
" | assert_well_formed_table 6
}

@test "renderer omits the Cost column when the adapter supplies no cost" {
  cat > "${SANDBOX}/nocost.json" <<'JSON'
{
  "schema": 1, "harness": "claudecode", "days": 30, "scope": "current",
  "scope_label": "/tmp/proj", "generated_at": "2026-09-10T16:40:00Z",
  "cost_kind": null,
  "tools": [{"name": "Bash", "count": 10, "tokens": 1234, "cost": null}],
  "mcp_servers": []
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/nocost.json"
  [ "${status}" -eq 0 ]
  refute_output --partial "Cost"
  assert_output --partial "Tokens"
  assert_output --partial "1,234"
}

@test "renderer reports an empty window gracefully" {
  cat > "${SANDBOX}/empty.json" <<'JSON'
{
  "schema": 1, "harness": "opencode", "days": 30, "scope": "all",
  "scope_label": "all projects", "generated_at": "2026-09-10T16:40:00Z",
  "cost_kind": "estimated", "tools": [], "mcp_servers": []
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/empty.json"
  [ "${status}" -eq 0 ]
  assert_output --partial "No tool usage"
}

@test "devbot stats fails with a FATAL when --days has no value" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --days
  [ "${status}" -ne 0 ]
  assert_output --partial "FATAL"
  assert_output --partial "--days"
}

@test "devbot stats fails with a FATAL when --harness has no value" {
  run bash "${PROJECT_ROOT}/bin/devbot" stats --harness
  [ "${status}" -ne 0 ]
  assert_output --partial "FATAL"
  assert_output --partial "--harness"
}

@test "devbot stats rejects an adapter payload with an unsupported schema" {
  mkdir -p "${ADAPTER_DIR}/opencode"
  cat > "${ADAPTER_DIR}/opencode/stats.sh" <<'SH'
#!/usr/bin/env bash
echo '{"schema": 2, "harness": "opencode", "days": 30, "scope": "current", "scope_label": "/x", "generated_at": "2026-01-01T00:00:00Z", "cost_kind": null, "tools": [], "mcp_servers": []}'
SH
  chmod +x "${ADAPTER_DIR}/opencode/stats.sh"
  make_project "opencode"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats"
  [ "${status}" -ne 0 ]
  assert_output --partial "FATAL"
  assert_output --partial "schema"
}

@test "renderer shows columns supplied only by MCP servers and pluralises the window" {
  cat > "${SANDBOX}/serveronly.json" <<'JSON'
{
  "schema": 1, "harness": "x", "days": 1, "scope": "current", "scope_label": "/p",
  "generated_at": "2026-09-10T16:40:00Z", "cost_kind": "estimated",
  "tools": [{"name": "bash", "count": 1, "tokens": null, "cost": null}],
  "mcp_servers": [{"server": "demo", "count": 1, "tokens": 50, "cost": 0.25,
                   "tools": [{"name": "foo", "count": 1, "tokens": 50, "cost": 0.25}]}]
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/serveronly.json"
  [ "${status}" -eq 0 ]
  assert_output --partial "Cost (est.)"
  assert_output --partial "Tokens"
  assert_output --partial "last 1 day"
  refute_output --partial "last 1 days"
}

@test "renderer rounds each table's Share column to sum to 100.0%" {
  cat > "${SANDBOX}/round.json" <<'JSON'
{
  "schema": 1, "harness": "x", "days": 30, "scope": "current", "scope_label": "/p",
  "generated_at": "2026-09-10T16:40:00Z", "cost_kind": null,
  "tools": [{"name": "a", "count": 1}, {"name": "b", "count": 1}, {"name": "c", "count": 1}],
  "mcp_servers": [{"server": "s1", "count": 1, "tools": []},
                  {"server": "s2", "count": 1, "tools": []},
                  {"server": "s3", "count": 1, "tools": []}]
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/round.json"
  [ "${status}" -eq 0 ]

  echo "${output}" | python3 -c "
import sys
sums = []
for block in sys.stdin.read().split('## '):
    lines = [l for l in block.splitlines() if l.strip().startswith('|')]
    if len(lines) < 3:
        continue
    header = [c.strip() for c in lines[0].strip('|').split('|')]
    if 'Share' not in header:
        continue
    idx = header.index('Share')
    total = 0.0
    for row in lines[2:]:
        cells = [c.strip() for c in row.strip('|').split('|')]
        total += float(cells[idx].rstrip('%'))
    sums.append(round(total, 1))
assert sums == [100.0, 100.0], sums
"
}

@test "renderer shows up to five MCP tools per server" {
  cat > "${SANDBOX}/top5.json" <<'JSON'
{
  "schema": 1, "harness": "x", "days": 30, "scope": "current", "scope_label": "/p",
  "generated_at": "2026-09-10T16:40:00Z", "cost_kind": null,
  "tools": [{"name": "bash", "count": 1}],
  "mcp_servers": [{"server": "demo", "count": 6, "tools": [
    {"name": "t1", "count": 6}, {"name": "t2", "count": 5}, {"name": "t3", "count": 4},
    {"name": "t4", "count": 3}, {"name": "t5", "count": 2}, {"name": "t6", "count": 1}]}]
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/top5.json"
  [ "${status}" -eq 0 ]
  assert_output --partial "t5 (2)"
  refute_output --partial "t6 (1)"
}

@test "renderer emits a Tool Arguments section" {
  cat > "${SANDBOX}/args.json" <<'JSON'
{
  "schema": 1, "harness": "x", "days": 30, "scope": "current", "scope_label": "/p",
  "generated_at": "2026-09-10T16:40:00Z", "cost_kind": null,
  "tools": [{"name": "bash", "count": 1}], "mcp_servers": [],
  "tool_arguments": {"bash": [{"value": "git status", "count": 338}],
                     "skill": [{"value": "devbot:make-plan", "count": 5}]}
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/args.json"
  [ "${status}" -eq 0 ]
  assert_output --partial "## Tool Arguments"
  assert_output --partial "### bash"
  assert_output --partial "git status"
  assert_output --partial "### skill"
  assert_output --partial "devbot:make-plan"
}

# ── Tool Grades section ───────────────────────────────────────────────────────

@test "renderer emits a Tool Grades section with averages and poor-rating reasons" {
  cat > "${SANDBOX}/grades.json" <<'JSON'
{
  "schema": 1, "harness": "x", "days": 30, "scope": "current", "scope_label": "/p",
  "generated_at": "2026-09-10T16:40:00Z", "cost_kind": null,
  "tools": [{"name": "bash", "count": 1}], "mcp_servers": [],
  "tool_grades": {
    "rows": 1, "total_rows": 3, "sessions": 3, "scope": "current",
    "tools": [
      {"column": "mcp:signoz", "name": "signoz", "kind": "mcp",
       "avg": 5.0, "uses": 1, "reasons": []},
      {"column": "skill:devbot:makefile", "name": "devbot:makefile", "kind": "skill",
       "avg": 2.33, "uses": 3,
       "reasons": [{"text": "Makefile covered it.", "count": 2}]},
      {"column": "mcp:datasources", "name": "datasources", "kind": "mcp",
       "avg": null, "uses": 0, "reasons": []}
    ]
  }
}
JSON

  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/grades.json"
  [ "${status}" -eq 0 ]

  assert_output --partial "## Tool Grades"
  assert_output --partial "highest first"
  assert_output --partial "not windowed"
  assert_output --partial "3 session(s)"
  assert_output --partial "2.33"
  assert_output --partial "—"
  assert_output --partial "devbot:makefile"
  assert_output --partial "signoz"
  assert_output --partial "### Poor ratings (1–3)"
  assert_output --partial "overall avg"
  assert_output --partial "Makefile covered it."
  assert_output --partial "(×2)"

  # Only the poorly-rated tool gets a reason bullet.
  echo "${output}" | python3 -c "
import sys
text = sys.stdin.read()
poor = text.split('### Poor ratings')[1]
assert 'devbot:makefile' in poor, poor
assert 'signoz' not in poor, poor
"
}

@test "renderer omits the Tool Grades section when the block is absent" {
  write_fixture
  run python3 "${PROJECT_ROOT}/src/_shared/render_stats.py" < "${SANDBOX}/fixture.json"
  [ "${status}" -eq 0 ]
  refute_output --partial "## Tool Grades"
}

# ── Tool Grades integration (parent reads the CSV) ────────────────────────────

@test "devbot stats appends the Tool Grades section when the grades CSV exists" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  write_grades_csv "Some-Other/project"
  export DEV_BOT_STATS_GRADES_CSV="${SANDBOX}/tools-grades.csv"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --all"
  [ "${status}" -eq 0 ]
  assert_output --partial "## Tool Grades"
  assert_output --partial "devbot:makefile"
  assert_output --partial "the Makefile covered it."
  assert_output --partial "(all projects)"
}

@test "devbot stats omits the Tool Grades section when the CSV is absent" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  export DEV_BOT_STATS_GRADES_CSV="${SANDBOX}/does-not-exist.csv"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats"
  [ "${status}" -eq 0 ]
  refute_output --partial "## Tool Grades"
}

@test "devbot stats includes grades from every project by default" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  write_grades_csv "Some-Other/project"
  export DEV_BOT_STATS_GRADES_CSV="${SANDBOX}/tools-grades.csv"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats"
  [ "${status}" -eq 0 ]
  assert_output --partial "## Tool Grades"
  assert_output --partial "devbot:makefile"
}

@test "devbot stats narrows tool grades with --project" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  write_grades_csv "Some-Other/project"
  export DEV_BOT_STATS_GRADES_CSV="${SANDBOX}/tools-grades.csv"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --project '${SANDBOX}'"
  [ "${status}" -eq 0 ]
  refute_output --partial "## Tool Grades"
}

@test "devbot stats warns and omits the section for a malformed grades CSV" {
  write_fixture
  install_fake_adapter "opencode" "${SANDBOX}/fixture.json"
  make_project "opencode"
  printf 'this is not,a grades csv\n' > "${SANDBOX}/bad-grades.csv"
  export DEV_BOT_STATS_GRADES_CSV="${SANDBOX}/bad-grades.csv"

  run bash -c "cd '${SANDBOX}' && bash '${PROJECT_ROOT}/bin/devbot' stats --all"
  [ "${status}" -eq 0 ]
  refute_output --partial "## Tool Grades"
  assert_output --partial "WARN:"
}


