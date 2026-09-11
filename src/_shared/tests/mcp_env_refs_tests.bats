#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp_env_refs_tests.bats
# Tests for the {env:VAR} presence check wired into init / reinit / harness
# start:
#
#   src/_shared/mcp_env_refs.py       — extractor: parse a canonical mcp.json
#                                       and print one `server<TAB>envkey<TAB>VAR`
#                                       line per whole-value {env:VAR} ref.
#   _devbot_missing_mcp_env_vars      — bash collector: scan the enabled modules
#                                       of a project, keep refs whose var is
#                                       unset/empty in the current shell env.
#   _devbot_present_missing_env_vars  — notice + prompt. Modes: ack (press any
#                                       key), gate (y/N — 1 on N), report
#                                       (notice only). DEV_BOT_DEFER_ENV_DIALOG=1,
#                                       SKIP_CONFIRM=1 and no-TTY collapse to
#                                       report (never block non-interactive).
#
# Run from project root:
#   bats src/_shared/tests/mcp_env_refs_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  EXTRACTOR="${PROJECT_ROOT}/src/_shared/mcp_env_refs.py"

  WORK="$(mktemp -d)"

  # ── Fake dev-bot root: hermetic module scan (real repo has signoz {env:}) ──
  export DEV_BOT_ROOT="${WORK}/root"
  mkdir -p "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" \
    "${DEV_BOT_ROOT}/src/harnesses"
  # Minimal global config: everything enabled.
  echo '{}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # agentic/envmod — one {env:} ref + one literal + one placeholder token.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/envmod"
  cat > "${DEV_BOT_ROOT}/src/agentic/envmod/mcp.json" <<'JSON_EOF'
{
  "mcp": {
    "envmod-server": {
      "type": "stdio",
      "command": ["envmod-mcp"],
      "env": { "ENVMOD_TOKEN": "{env:ENVMOD_SECRET}", "LOG_LEVEL": "info", "HOME_DIR": "{harness-dir}/envmod" }
    }
  }
}
JSON_EOF

  # agentic/plain — no env indirection at all.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/plain"
  cat > "${DEV_BOT_ROOT}/src/agentic/plain/mcp.json" <<'JSON_EOF'
{
  "mcp": {
    "plain-server": { "type": "stdio", "command": ["plain-mcp"] }
  }
}
JSON_EOF

  # agentic/plugmod — MCP provided via opencode plugin: registration skips it,
  # so its {env:} refs must not be reported either.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/plugmod"
  echo '{}' > "${DEV_BOT_ROOT}/src/agentic/plugmod/plugin.opencode.json"
  cat > "${DEV_BOT_ROOT}/src/agentic/plugmod/mcp.json" <<'JSON_EOF'
{
  "mcp": {
    "plug-server": {
      "type": "stdio",
      "command": ["plug-mcp"],
      "env": { "PLUG_TOKEN": "{env:PLUG_SECRET}" }
    }
  }
}
JSON_EOF

  # tools/toolenv — a second module sharing the SAME env var (union/dedupe).
  mkdir -p "${DEV_BOT_ROOT}/src/tools/toolenv"
  cat > "${DEV_BOT_ROOT}/src/tools/toolenv/mcp.json" <<'JSON_EOF'
{
  "mcp": {
    "toolenv-server": {
      "type": "stdio",
      "command": ["toolenv-mcp"],
      "env": { "TOOLENV_KEY": "{env:ENVMOD_SECRET}" }
    }
  }
}
JSON_EOF

  # Project dir with a per-project config (used by the disabled-module test).
  PROJECT="${WORK}/project"
  mkdir -p "${PROJECT}"
  echo '{}' > "${PROJECT}/.devbot.project.jsonc"

  # Runtime manifest written by a module init (.opencode/<name>.mcp.json) — no
  # canonical mcp.json, indirection lives in headers. jetbrains is the real case.
  mkdir -p "${PROJECT}/.opencode"
  cat > "${PROJECT}/.opencode/jetbrains.mcp.json" <<'JSON_EOF'
{
  "jetbrains": {
    "type": "remote",
    "url": "http://127.0.0.1:64442/stream",
    "headers": { "IJ_MCP_SERVER_PROJECT_PATH": "{env:JET_DYN_SECRET}" },
    "enabled": true
  }
}
JSON_EOF

  # Source the REAL shared library (collector + presenter live there).
  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # Clean env for presence checks — ensure the fixture vars are unset.
  unset ENVMOD_SECRET PLUG_SECRET JET_DYN_SECRET 2>/dev/null || true
}

teardown() {
  unset DEV_BOT_ROOT ENVMOD_SECRET PLUG_SECRET JET_DYN_SECRET 2>/dev/null || true
  rm -rf "${WORK}" 2>/dev/null || true
}

# ── Extractor CLI (mcp_env_refs.py) ───────────────────────────────────────────

@test "extractor prints one server<TAB>envkey<TAB>VAR line per {env:VAR} ref" {
  run python3 "${EXTRACTOR}" "${DEV_BOT_ROOT}/src/agentic/envmod/mcp.json"
  assert_success
  assert_output "envmod-server	ENVMOD_TOKEN	ENVMOD_SECRET"
}

@test "extractor ignores literal values and non-env placeholder tokens" {
  run python3 "${EXTRACTOR}" "${DEV_BOT_ROOT}/src/agentic/envmod/mcp.json"
  assert_success
  refute_output --partial "LOG_LEVEL"
  refute_output --partial "harness-dir"
}

@test "extractor ignores underscore-prefixed annotation server keys" {
  cat > "${WORK}/annotated.json" <<'JSON_EOF'
{
  "mcp": {
    "_note": "annotation — must not appear",
    "real-server": { "type": "stdio", "command": ["mcp"], "env": { "K": "{env:REAL_SECRET}" } }
  }
}
JSON_EOF
  run python3 "${EXTRACTOR}" "${WORK}/annotated.json"
  assert_success
  assert_output "real-server	K	REAL_SECRET"
}

@test "extractor prints nothing for a manifest without env indirection" {
  run python3 "${EXTRACTOR}" "${DEV_BOT_ROOT}/src/agentic/plain/mcp.json"
  assert_success
  assert_output ""
}

@test "extractor fails loudly on a missing manifest" {
  run python3 "${EXTRACTOR}" "${WORK}/nope.json"
  assert_failure
}

@test "extractor reads a runtime manifest's {env:VAR} from headers" {
  cat > "${WORK}/runtime.mcp.json" <<'JSON_EOF'
{
  "jetbrains": {
    "type": "remote",
    "url": "http://127.0.0.1:64442/stream",
    "headers": { "IJ_MCP_SERVER_PROJECT_PATH": "{env:HOST_PATH}" },
    "enabled": true
  }
}
JSON_EOF
  run python3 "${EXTRACTOR}" "${WORK}/runtime.mcp.json"
  assert_success
  assert_output "jetbrains	IJ_MCP_SERVER_PROJECT_PATH	HOST_PATH"
}

# ── Bash collector (_devbot_missing_mcp_env_vars) ─────────────────────────────

@test "collector reports an unset {env:VAR} with module context" {
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  assert_output --partial "envmod|envmod-server|ENVMOD_TOKEN|ENVMOD_SECRET"
  assert_output --partial "toolenv|toolenv-server|TOOLENV_KEY|ENVMOD_SECRET"
}

@test "collector stays silent when the env var is set" {
  export ENVMOD_SECRET="present" JET_DYN_SECRET="present"
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  assert_output ""
}

@test "collector treats an exported-but-empty var as missing" {
  export ENVMOD_SECRET=""
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  assert_output --partial "ENVMOD_SECRET"
}

@test "collector skips modules disabled in the project config" {
  cat > "${PROJECT}/.devbot.project.jsonc" <<'JSON_EOF'
{ "modules": { "envmod": false } }
JSON_EOF
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  refute_output --partial "envmod"
  assert_output --partial "toolenv"
}

@test "collector skips plugin-provided modules (registration skips them)" {
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  refute_output --partial "plugmod"
  refute_output --partial "PLUG_SECRET"
}

@test "collector reports a runtime manifest ref, labelled by manifest name" {
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  assert_output --partial "jetbrains|jetbrains|IJ_MCP_SERVER_PROJECT_PATH|JET_DYN_SECRET"
}

@test "collector skips a runtime manifest for a disabled module" {
  cat > "${PROJECT}/.devbot.project.jsonc" <<'JSON_EOF'
{ "modules": { "jetbrains": false } }
JSON_EOF
  run _devbot_missing_mcp_env_vars "${PROJECT}"
  assert_success
  refute_output --partial "JET_DYN_SECRET"
}

# ── Notice + prompt (_devbot_present_missing_env_vars) ────────────────────────

@test "presenter notice names the var, module and the .bashrc + new-terminal hint" {
  run _devbot_present_missing_env_vars \
    "$(_devbot_missing_mcp_env_vars "${PROJECT}")" report
  assert_success
  assert_output --partial "ENVMOD_SECRET"
  assert_output --partial "envmod"
  assert_output --partial "export ENVMOD_SECRET=..."
  assert_output --partial ".bashrc"
  assert_output --regexp "[Nn][Ee][Ww] terminal"
}

@test "presenter ack mode collapses to report under SKIP_CONFIRM (no prompt, exit 0)" {
  SKIP_CONFIRM=1 run _devbot_present_missing_env_vars \
    "$(_devbot_missing_mcp_env_vars "${PROJECT}")" ack
  assert_success
  assert_output --partial "ENVMOD_SECRET"
  refute_output --partial "Press any key"
}

@test "presenter gate mode collapses to report under SKIP_CONFIRM (launch anyway)" {
  SKIP_CONFIRM=1 run _devbot_present_missing_env_vars \
    "$(_devbot_missing_mcp_env_vars "${PROJECT}")" gate
  assert_success
  assert_output --partial "ENVMOD_SECRET"
  refute_output --partial "Launch the harness anyway"
}

@test "presenter stays silent when there is nothing missing" {
  run _devbot_present_missing_env_vars "" report
  assert_success
  assert_output ""
}

@test "presenter defer mode emits a compact notice, not the full guidance" {
  DEV_BOT_DEFER_ENV_DIALOG=1 run _devbot_present_missing_env_vars \
    "$(_devbot_missing_mcp_env_vars "${PROJECT}")" ack
  assert_success
  assert_output --partial "unset env var(s)"
  assert_output --partial "ENVMOD_SECRET"
  assert_output --partial "full notice at end of reinit"
  refute_output --partial ".bashrc"
  refute_output --partial "Press any key"
}

@test "check wrapper returns 0 silently when no refs are missing" {
  export ENVMOD_SECRET="present" JET_DYN_SECRET="present"
  run _devbot_check_mcp_env_vars "${PROJECT}" ack
  assert_success
  assert_output ""
}
