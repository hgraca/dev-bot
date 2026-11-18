#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/agent_names_tests.bats
# Guards the lowercase agent-name convention across both agent modules
# (`devbot/agents` and `devteam/agents`).
#
# The harness resolves `subagent_type` case-sensitively, so a `name:` that does
# not match its lowercase filename is unreachable; a capitalised @handle sends
# the reader to a name the registry does not have.
#
# Run from project root:
#   bats src/agentic/devteam/tests/agent_names_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  AGENT_FILES=("${ROOT}"/src/agentic/*/agents/*.md)
}

@test "every agent declares a lowercase name matching its filename" {
  local failures=0 file name stem
  for file in "${AGENT_FILES[@]}"; do
    name="$(sed -n 's/^name: *//p' "${file}" | head -1)"
    stem="$(basename "${file}" .md)"
    if [[ ! "${name}" =~ ^[a-z][a-z0-9-]*$ ]]; then
      echo "${file#"${ROOT}"/}: name '${name}' is not lowercase"
      failures=$((failures + 1))
    fi
    if [[ "${name}" != "${stem}" ]]; then
      echo "${file#"${ROOT}"/}: name '${name}' does not match '${stem}'"
      failures=$((failures + 1))
    fi
  done
  [ "${failures}" -eq 0 ]
}

@test "agent names are unique across modules" {
  local duplicates
  duplicates="$(sed -n 's/^name: *//p' "${AGENT_FILES[@]}" | sort | uniq -d)"
  [ -z "${duplicates}" ]
}

@test "no agent is mentioned with a capitalised @handle" {
  run grep -rEn '@(DevBot|TeamLead|Scout|PO|Architect|Critic|Developer|Reviewer|Tester|Security|Designer|Expert)\b' \
    "${ROOT}/src" "${ROOT}/bin" "${ROOT}/docs" \
    --include='*.md' --include='*.md.tpl' \
    --exclude-dir=_site --exclude-dir=node_modules
  # 1 is "no match"; 2 would be a broken path or pattern, not a pass.
  assert_equal "${status}" 1
}

@test "every opencode agent override targets a declared agent" {
  local keys key unknown=""
  keys="$(python3 "${ROOT}/src/_shared/read_jsonc.py" \
    "${ROOT}/src/harnesses/opencode/opencode.dist.jsonc" agent 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin).keys()))')"
  [ -n "${keys}" ]

  for key in ${keys}; do
    # `plan` and `build` are opencode built-ins the dist disables.
    [[ "${key}" == "plan" || "${key}" == "build" ]] && continue
    grep -q "^name: ${key}$" "${AGENT_FILES[@]}" || unknown="${unknown} ${key}"
  done

  [ -z "${unknown}" ] || { echo "overrides for undeclared agents:${unknown}"; return 1; }
}

@test "the opencode default agent names a declared agent" {
  local default_agent
  default_agent="$(sed -n 's/^ *"default_agent": *"\([^"]*\)".*/\1/p' \
    "${ROOT}/src/harnesses/opencode/opencode.dist.jsonc")"
  [ -n "${default_agent}" ]

  run grep -l "^name: ${default_agent}$" "${AGENT_FILES[@]}"
  assert_success
}

# ── OpenCode 2: an agent id is the FLAT path below .opencode/agents ──────────
# A 2.x host derives the id from the path (`.opencode/agents/devbot/devbot.md`
# registers as `devbot/devbot`), and an `agents` config entry becomes an agent
# of its own when no file agent carries that id — with no `system` prompt at
# all. A bare-name entry pointing at a namespaced file agent therefore boots a
# prompt-less session: no persona, no session-start rules, no skill loading.
# These two assert the dist's names are the flat ones the farm links.

@test "every opencode-v2 agent override targets a declared agent" {
  local keys key unknown=""
  keys="$(python3 "${ROOT}/src/_shared/read_jsonc.py" \
    "${ROOT}/src/harnesses/opencode-v2/opencode-v2.dist.jsonc" agents 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin).keys()))')"
  [ -n "${keys}" ]

  for key in ${keys}; do
    # `plan` and `build` are opencode built-ins the dist disables.
    [[ "${key}" == "plan" || "${key}" == "build" ]] && continue
    grep -q "^name: ${key}$" "${AGENT_FILES[@]}" || unknown="${unknown} ${key}"
  done

  [ -z "${unknown}" ] || { echo "overrides for undeclared agents:${unknown}"; return 1; }
}

@test "the opencode-v2 default agent names a declared agent" {
  local default_agent
  default_agent="$(sed -n 's/^ *"default_agent": *"\([^"]*\)".*/\1/p' \
    "${ROOT}/src/harnesses/opencode-v2/opencode-v2.dist.jsonc")"
  [ -n "${default_agent}" ]

  run grep -l "^name: ${default_agent}$" "${AGENT_FILES[@]}"
  assert_success
}
