#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── Skeleton ───────────────────────────────────────────────────────────────────

@test "functions.sh: sources cleanly and exposes shared helpers" {
  run bash -c "source '${MODULE_DIR}/functions.sh' && declare -F _info >/dev/null && declare -F _warn >/dev/null"
  assert_success
}

@test "pre.sh: exits 0" {
  run bash "${MODULE_DIR}/pre.sh"
  assert_success
}

@test "install.sh: is idempotent (second run succeeds)" {
  run bash "${MODULE_DIR}/install.sh"
  assert_success

  run bash "${MODULE_DIR}/install.sh"
  assert_success
}

# ── Tool contract: CLI surface, not an MCP tool (T2) ───────────────────────────
#
# The tool is a plain CLI: the `devbot:refactor` skill documents it and an agent
# runs it as `devbot tool refactor <op> …`. It must NOT answer mcp-meta — that
# is what would register it on the shared devbot-tools MCP server.

@test "not an MCP tool: no .mcp.sh wrapper and no mcp-meta subcommand" {
  run bash -c "ls '${MODULE_DIR}'/tools/*.mcp.sh 2>/dev/null"
  assert_failure

  run bash "${TOOL}" mcp-meta
  assert_failure
}

@test "--version: prints the tool version and exits 0" {
  run bash "${TOOL}" --version
  assert_success
  assert_output --regexp "^refactor [0-9]+\.[0-9]+\.[0-9]+$"
}

@test "--help: prints usage and exits 0" {
  run bash "${TOOL}" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "no args: reports an ERROR and exits non-zero" {
  run bash "${TOOL}"
  assert_failure
  assert_output --partial "ERROR:"
}

# ── Plugin seam: registry + dispatch (T3) ──────────────────────────────────────
#
# The stublang fixture is a language the core has never heard of, discovered
# purely because it sits under REFACTOR_LANGS_DIR. These tests are the
# additivity proof: a new language needs no edit to the core.

@test "plugin seam: dispatches to a language discovered from REFACTOR_LANGS_DIR" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang rename \
    --class 'App\Foo' --method old --to new

  assert_success
  assert_output --partial "## refactor: rename"
  assert_output --partial "**Engine:** stub 1.0.0"
  assert_output --partial "old -> new"
}

@test "plugin seam: forwards --apply to the plugin" {
  command -v git >/dev/null 2>&1 || skip "git not installed"

  # Inside a clean throwaway repo: the core refuses --apply on a dirty tree, and
  # this test must not depend on the surrounding checkout's state.
  local repo
  repo="$(mktemp -d)"
  git -C "${repo}" init -q

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --method old --to new --apply --json"
  rm -rf "${repo}"

  assert_success
  assert_output --partial '"applied": true'
}

@test "plugin seam: the request contract survives the hop" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang rename \
    --class 'App\Foo' --method old --to new --json

  assert_success
  assert_output --partial '"op": "rename-method"'
  assert_output --partial '"from": "old"'
  assert_output --partial '"to": "new"'
}

@test "plugin seam: unknown language lists what is available" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang nope rename --class X --method a --to b

  assert_failure
  assert_output --partial "unknown language 'nope'"
  assert_output --partial "available: stublang"
}

@test "plugin seam: an op the plugin does not declare is rejected" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang move --class X --to b

  assert_failure
  assert_output --partial "does not support op 'move'"
}

@test "plugin seam: an empty langs dir yields no available languages" {

  local empty
  empty="$(mktemp -d)"
  export REFACTOR_LANGS_DIR="${empty}"

  run bash "${TOOL}" --lang php rename --class X --method a --to b
  rm -rf "${empty}"

  assert_failure
  assert_output --partial "unknown language 'php'"
  assert_output --partial "available: none"
}

@test "plugin seam: the core forwards --file to the plugin" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --from a --to b --file stub/x.stub --json"

  assert_success
  assert_output --partial '"file": "stub/x.stub"'
}

@test "plugin seam: the core forwards --kind to the plugin" {
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --from a --to b --kind method --json"

  assert_success
  assert_output --partial '"kind": "method"'
}

@test "plugin seam: a kind the plugin does not declare is rejected" {
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --from a --to b --kind class"

  assert_failure
  assert_output --partial "does not support kind 'class'"
}

@test "core: the markdown report names the op's risk class" {
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --method old --to new"

  assert_success
  assert_output --partial "**Risk:** rename"
}

@test "core: resolve reports the native op's risk class" {
  run env REFACTOR_LANGS_DIR="${MODULE_DIR}/langs" python3 "${MODULE_DIR}/lib/refactor-lib.py" \
    resolve --op rename --lang ts --from a --to b

  assert_success
  assert_output --partial '"risk": "rename"'
}

# ── Core: language resolution and error branches ───────────────────────────────

@test "core: an op several languages declare needs --file or --lang" {
  run bash -c "REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' privatize"

  assert_failure
  assert_output --partial "exists in several languages"
}

@test "core: a file whose extension matches no language is refused" {
  run bash -c "REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' rename --file notes.xyz --from a --to b"

  assert_failure
  assert_output --partial "cannot infer a language"
}

@test "core: an op with several kinds needs --kind" {
  run bash -c "REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' --lang php rename --class X --from a --to b"

  assert_failure
  assert_output --partial "needs --kind"
}

@test "core: a plugin that declares no map is refused" {
  run bash -c "REFACTOR_LANGS_DIR='${EDGE_LANGS}' bash '${TOOL}' --lang nomaplang rename --from a --to b"

  assert_failure
  assert_output --partial "exposes no map for op 'rename'"
}

@test "core: a plugin that answers with invalid JSON is reported" {
  run bash -c "REFACTOR_LANGS_DIR='${EDGE_LANGS}' bash '${TOOL}' --lang badlang rename --class X --from a --to b"

  assert_failure
  assert_output --partial "the plugin returned invalid JSON"
}

@test "plugin seam: the core forwards --start/--end/--index/--default" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --from a --to b --start 2:3 --end 9 --index 4 --default 'z' --json"

  assert_success
  assert_output --partial '"start": "2:3"'
  assert_output --partial '"end": "9"'
  assert_output --partial '"index": "4"'
  assert_output --partial '"default": "z"'
}

@test "plugin seam: an extract op drives through the core to the py plugin" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/extract-demo/." "${work}/"

  run bash -c "cd '${work}' && REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' --lang py extract --kind method --file src/calc.py --start 2 --end 3 --to compute --json"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
}

@test "plugin seam: the markdown report shows the references a rename cannot reach" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' --lang py rename --from greet --to salute"
  rm -rf "${work}"

  assert_success
  # Default (markdown), not --json: the residual string references must show.
  assert_output --partial 'String references'
}

# ── Documentation: one ops table, always in sync with the plugins ──────────────

@test "docs: the ops table is identical in SKILL.md and docs.md, and matches the plugins" {
  run python3 "${TEST_DIR}/ops_table_check.py" "${MODULE_DIR}"
  assert_success
  assert_output --partial "ops table in sync"
}
