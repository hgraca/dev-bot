#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_tests.bats
# Tests for bin/init.sh: external module init loop (Task 2) and
# memory folder linking (Task 3).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Resolve project root
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # Create a unique sandbox per test (cleaned in teardown)
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# ── Helpers ────────────────────────────────────────────────────────────────

# _setup <json_config>
# Creates sandbox with minimal dev-bot structure for testing init functions.
_setup() {
  local json_content="${1:-{\}}"

  mkdir -p "${SANDBOX_DIR}/bin"
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  mkdir -p "${SANDBOX_DIR}/src/agentic"
  mkdir -p "${SANDBOX_DIR}/src/tools"
  mkdir -p "${SANDBOX_DIR}/storage/external-agentic-modules"
  mkdir -p "${SANDBOX_DIR}/.agents/memory"

  # Minimal functions.sh
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'FUNCTIONS_EOF'
#!/usr/bin/env bash
TEXT_BOLD=''; TEXT_GREEN=''; TEXT_BLUE=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''; TEXT_DIM=''; TEXT_CLEAR=''
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_log()  { echo "LOG: $*"; }
_step() { echo "STEP: $*"; }
_header_1() { echo "HEADER1: $1"; }
_header_2() { echo "HEADER2: $1"; }
_header_3() { echo "HEADER3: $*"; }
_fmt_duration() { echo "0s"; }
_qmd_gpu_value() { echo "false"; }

_devbot_get_disabled_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.jsonc"
  [[ ! -f "${config}" ]] && echo "[]" && return 0
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    states = data.get('modules', {})
    print(json.dumps(sorted(m for m, v in states.items() if v is False)))
except:
    print('[]')
" "${config}" 2>/dev/null || echo "[]"
}

_devbot_get_project_dir() { echo ".agents"; }

_devbot_get_external_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.jsonc"
  [[ ! -f "${config}" ]] && return 0
  python3 -c "
import json
try:
    with open('${config}') as f:
        data = json.load(f)
    for name in (data.get('external_modules') or {}):
        print(name)
except Exception:
    pass
" 2>/dev/null || true
}
FUNCTIONS_EOF

  # Append the REAL _mcp_declares_hybrid from the shipped library: the docker
  # guard tests below must exercise the actual predicate, not a copy that can
  # drift from it. The rest of functions.sh stays stubbed for isolation.
  sed -n '/^_mcp_declares_hybrid() {/,/^}$/p' \
    "${PROJECT_ROOT}/src/_shared/functions.sh" \
    >> "${SANDBOX_DIR}/src/_shared/functions.sh"

  # The real python helpers the registration path invokes (mcp_translate,
  # merge_mcp_jsonc, read_jsonc) so _register_module_mcp runs unfaked.
  cp "${PROJECT_ROOT}"/src/_shared/*.py "${SANDBOX_DIR}/src/_shared/"

  # Copy init.sh (without main call)
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX_DIR}/bin/init.sh"

  # Create .devbot.jsonc
  printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.jsonc"
}

# _add_external_module <name> [init_exit_code]
# Creates an external module storage entry AND registers it in the config
# (.devbot.jsonc::modules) — the config is the source of truth.
_add_external_module() {
  local name="$1"
  local exit_code="${2:-0}"
  local dir="${SANDBOX_DIR}/storage/external-agentic-modules/${name}"
  mkdir -p "${dir}"

  cat > "${dir}/init.sh" <<EOF
#!/usr/bin/env bash
echo "${name}_init_called"
exit ${exit_code}
EOF
  chmod +x "${dir}/init.sh"

  # Create a memory subfolder
  mkdir -p "${dir}/memory"
  echo "# ${name} memory" > "${dir}/memory/note.md"

  # Register in config
  python3 -c "
import json
config = '${SANDBOX_DIR}/.devbot.jsonc'
with open(config) as f:
    data = json.load(f)
data.setdefault('external_modules', {})['${name}'] = {'url': 'https://example.com/${name}.git', 'paths': {}}
with open(config, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
}

# _add_orphan_storage <name> — create a storage dir with NO config entry.
_add_orphan_storage() {
  local name="$1"
  local dir="${SANDBOX_DIR}/storage/external-agentic-modules/${name}"
  mkdir -p "${dir}/memory"
  echo "# orphan" > "${dir}/memory/note.md"
}

# _run <func_name> [args...]
# Sets up env, sources files, runs the requested init function.
# Must save args before sourcing init.sh to prevent PROJECT_DIR
# from picking up leaked positional parameters.
_run() {
  local func="$1"
  shift
  local saved_args=("$@")

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/src/_shared/functions.sh"
  set --
  source "${SANDBOX_DIR}/bin/init.sh"
  # Override PROJECT_DIR after init.sh sets it, so _link_memory_folders
  # creates links in the sandbox, not the cwd.
  export PROJECT_DIR="${SANDBOX_DIR}"
  "${func}" "${saved_args[@]}"
}

# ── Tests: External module init loop (Task 2) ──────────────────────────────

@test "init loop: runs init.sh from external agentic module" {
  _setup '{}'
  _add_external_module "test-ext" 0

  run _run _run_inits
  assert_success
  assert_output --partial "test-ext_init_called"
}

@test "init loop: skips external module that lacks init.sh" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/storage/external-agentic-modules/no-init-mod"
  # Register in config, but no init.sh present
  python3 -c "
import json
config = '${SANDBOX_DIR}/.devbot.jsonc'
with open(config) as f:
    data = json.load(f)
data.setdefault('external_modules', {})['no-init-mod'] = {'url': 'https://example.com/no-init-mod.git', 'paths': {}}
with open(config, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  run _run _run_inits
  assert_success
  [[ "$output" != *"no-init-mod"* ]]
}

@test "init loop: ignores storage dirs not present in config" {
  _setup '{}'
  _add_orphan_storage "orphan-mod"
  _add_external_module "configured-mod" 0

  run _run _run_inits
  assert_success
  refute_output --partial "orphan-mod"
  assert_output --partial "configured-mod_init_called"
}

@test "init loop: external module init failure does not abort" {
  _setup '{}'
  _add_external_module "failing-ext" 1

  run _run _run_inits
  assert_success
  assert_output --partial "had issues"
}

@test "init loop: disabled_modules filtering applies to external modules" {
  _setup '{"modules": {"disabled-ext": false}}'
  _add_external_module "disabled-ext" 0
  _add_external_module "enabled-ext" 0

  run _run _run_inits
  assert_success
  assert_output --partial "disabled-ext: disabled per config"
  assert_output --partial "enabled-ext_init_called"
}

@test "init loop: multiple external modules all run" {
  _setup '{}'
  _add_external_module "ext-a" 0
  _add_external_module "ext-b" 0
  _add_external_module "ext-c" 0

  run _run _run_inits
  assert_success
  assert_output --partial "ext-a_init_called"
  assert_output --partial "ext-b_init_called"
  assert_output --partial "ext-c_init_called"
}

@test "init loop: no external modules directory is harmless" {
  _setup '{}'
  rm -rf "${SANDBOX_DIR}/storage/external-agentic-modules"

  run _run _run_inits
  assert_success
}

# ── Tests: Memory linking (Task 3) ─────────────────────────────────────────

@test "memory link: creates symlink for built-in agentic module memory" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/test-module/memory"
  echo "# test memory" > "${SANDBOX_DIR}/src/agentic/test-module/memory/test.md"

  run _run _link_memory_folders
  assert_success

  assert [ -L "${SANDBOX_DIR}/.agents/memory/test-module" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/test-module")" = "${SANDBOX_DIR}/src/agentic/test-module/memory" ]
}

@test "memory link: creates individual file symlinks for external module memory" {
  _setup '{}'
  _add_external_module "ext-mod" 0

  run _run _link_memory_folders
  assert_success

  # External modules create individual file symlinks at the paths specified
  # in the storage structure — note.md (no module-name wrapper)
  local expected_src="${SANDBOX_DIR}/storage/external-agentic-modules/ext-mod/memory/note.md"
  assert [ -L "${SANDBOX_DIR}/.agents/memory/note.md" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/note.md")" = "${expected_src}" ]
}

@test "memory link: skips modules without memory/ directory" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/no-memory-mod"
  mkdir -p "${SANDBOX_DIR}/src/agentic/has-memory/memory"
  echo "x" > "${SANDBOX_DIR}/src/agentic/has-memory/memory/m.md"

  run _run _link_memory_folders
  assert_success

  assert [ -L "${SANDBOX_DIR}/.agents/memory/has-memory" ]
  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/no-memory-mod" ]
}

@test "memory link: idempotent — re-running does not change correct symlinks" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/mymod/memory"
  echo "x" > "${SANDBOX_DIR}/src/agentic/mymod/memory/m.md"

  run _run _link_memory_folders
  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/memory/mymod" ]

  run _run _link_memory_folders
  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/memory/mymod" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/mymod")" = "${SANDBOX_DIR}/src/agentic/mymod/memory" ]
}

@test "memory link: built-in and external modules both linked" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/built-in-mod/memory"
  echo "b" > "${SANDBOX_DIR}/src/agentic/built-in-mod/memory/b.md"
  _add_external_module "external-mod" 0

  run _run _link_memory_folders
  assert_success

  # Built-in: dir symlink under module name
  assert [ -L "${SANDBOX_DIR}/.agents/memory/built-in-mod" ]
  # External: individual file symlinks at root (not under module name)
  assert [ -L "${SANDBOX_DIR}/.agents/memory/note.md" ]
  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/external-mod" ]
}

@test "memory link: disabled_modules skips linking for disabled modules" {
  _setup '{"modules": {"disabled-mod": false}}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/disabled-mod/memory"
  echo "d" > "${SANDBOX_DIR}/src/agentic/disabled-mod/memory/d.md"
  mkdir -p "${SANDBOX_DIR}/src/agentic/enabled-mod/memory"
  echo "e" > "${SANDBOX_DIR}/src/agentic/enabled-mod/memory/e.md"

  run _run _link_memory_folders
  assert_success

  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/disabled-mod" ]
  assert [ -L "${SANDBOX_DIR}/.agents/memory/enabled-mod" ]
}

# ── Tests: orphaned external module pruning ────────────────────────────────

@test "prune: removes storage dirs not present in modules config" {
  _setup '{}'
  _add_orphan_storage "orphan-a"
  _add_orphan_storage "orphan-b"
  _add_external_module "keep-me" 0

  run _run _prune_orphaned_external_modules
  assert_success

  assert [ ! -e "${SANDBOX_DIR}/storage/external-agentic-modules/orphan-a" ]
  assert [ ! -e "${SANDBOX_DIR}/storage/external-agentic-modules/orphan-b" ]
  assert [ -d "${SANDBOX_DIR}/storage/external-agentic-modules/keep-me" ]
}

@test "prune: harmless when no external modules directory" {
  _setup '{}'
  rm -rf "${SANDBOX_DIR}/storage/external-agentic-modules"

  run _run _prune_orphaned_external_modules
  assert_success
}

@test "prune: removes a mirror declared by a disabled umbrella module" {
  _setup '{"modules": {"off-umbrella": false}}'
  # A disabled umbrella declares ext-decl; init skips it entirely (audit-03 §9),
  # so a mirror left by an earlier state is an orphan.
  mkdir -p "${SANDBOX_DIR}/src/agentic/off-umbrella"
  cat > "${SANDBOX_DIR}/src/agentic/off-umbrella/external-modules.json" <<'EOF'
{
  "ext-decl": { "url": "https://example.com/ext-decl.git", "paths": { "skills": "skills" } }
}
EOF
  _add_external_module "ext-decl" 0

  run _run _prune_orphaned_external_modules
  assert_success

  assert [ ! -e "${SANDBOX_DIR}/storage/external-agentic-modules/ext-decl" ]
}

@test "prune: keeps a mirror declared by an enabled umbrella module" {
  _setup '{"modules": {"on-umbrella": true}}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/on-umbrella"
  cat > "${SANDBOX_DIR}/src/agentic/on-umbrella/external-modules.json" <<'EOF'
{
  "ext-kept": { "url": "https://example.com/ext-kept.git", "paths": { "skills": "skills" } }
}
EOF
  _add_external_module "ext-kept" 0

  run _run _prune_orphaned_external_modules
  assert_success

  assert [ -d "${SANDBOX_DIR}/storage/external-agentic-modules/ext-kept" ]
}

@test "prune: keeps a mirror declared by both an enabled and a disabled module" {
  # A disabled umbrella declaring the name is not enough to orphan it: the
  # enabled umbrella needs the mirror (audit-03 review F3).
  _setup '{"modules": {"off-umbrella": false, "on-umbrella": true}}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/off-umbrella" "${SANDBOX_DIR}/src/agentic/on-umbrella"
  cat > "${SANDBOX_DIR}/src/agentic/off-umbrella/external-modules.json" <<'EOF'
{ "shared-name": { "url": "https://example.com/shared-name.git", "paths": { "skills": "skills" } } }
EOF
  cat > "${SANDBOX_DIR}/src/agentic/on-umbrella/external-modules.json" <<'EOF'
{ "shared-name": { "url": "https://example.com/shared-name.git", "paths": { "skills": "skills" } } }
EOF
  _add_external_module "shared-name" 0

  run _run _prune_orphaned_external_modules
  assert_success

  assert [ -d "${SANDBOX_DIR}/storage/external-agentic-modules/shared-name" ]
}

# ── Tests: docker-only MCP registration guard ──────────────────────────────
# The guard skips an MCP that can only run under docker when no daemon is
# available, so the client never starts a server that cannot come up. A hybrid
# server — a docker path plus a non-docker fallback its own launcher picks —
# must stay REGISTERED. The guard used to grep the translated command for the
# literal `npx -y @playwright/mcp`; e7e7cd40 replaced that fallback, so the
# literal stopped matching and playwright was silently dropped from every
# daemon-less host. It now consults the manifest's `"_hybrid": true`
# declaration (via the real _mcp_declares_hybrid appended in _setup).

# _add_docker_mcp_module <name> <hybrid|plain> — a module whose MCP declares a
# docker launch path (and, for "hybrid", a runtime-picked non-docker fallback).
_add_docker_mcp_module() {
  local name="$1" kind="$2"
  local dir="${SANDBOX_DIR}/src/agentic/${name}"
  mkdir -p "${dir}"

  local annotation=""
  [[ "${kind}" == "hybrid" ]] && annotation='"_hybrid": true,'

  cat > "${dir}/mcp.json" <<JSON_EOF
{
  "mcp": {
    "${name}": {
      "type": "stdio",
      ${annotation}
      "command": ["bash", "-c", "if docker info >/dev/null 2>&1; then exec docker run --rm -i img; else exec fallback --serve; fi"]
    }
  }
}
JSON_EOF
}

# _stub_docker <status> — a fake `docker` on PATH whose every invocation exits
# with the given status, so the guard's daemon probe is deterministic.
_stub_docker() {
  local status="$1"
  mkdir -p "${SANDBOX_DIR}/stub-bin"
  cat > "${SANDBOX_DIR}/stub-bin/docker" <<EOF
#!/usr/bin/env bash
exit ${status}
EOF
  chmod +x "${SANDBOX_DIR}/stub-bin/docker"
  export PATH="${SANDBOX_DIR}/stub-bin:${PATH}"
}

# _register_mcp <module-name> — run the real registration for a sandbox module.
_register_mcp() {
  local name="$1"

  # merge_mcp_jsonc.py requires the config to exist (it does not create it).
  printf '{}\n' > "${SANDBOX_DIR}/opencode.jsonc"

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/src/_shared/functions.sh"
  # init.sh's top-level code resolves PROJECT_DIR from $1 — clear the leaked
  # positional parameter first (same hazard _run documents).
  set --
  source "${SANDBOX_DIR}/bin/init.sh"
  export PROJECT_DIR="${SANDBOX_DIR}"

  # mod_dir must keep its trailing slash: _register_module_mcp derives
  # mcp_file="${mod_dir}mcp.json" (the real caller's `"${base_dir}/"*/` glob
  # supplies one).
  _register_module_mcp "${SANDBOX_DIR}/src/agentic/${name}/" \
    "${SANDBOX_DIR}/opencode.jsonc" "opencode.jsonc"
}

# _assert_registered <module-name> <ok|absent>
_assert_registered() {
  local name="$1" expect="$2"
  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
present = '${name}' in mcp
assert present == (('${expect}' == 'ok')), (present, mcp)
print('MCP-STATE:OK')
"
  assert_success
  grep -qF 'MCP-STATE:OK' <<< "$output" || fail "${name} registration state wrong (expected ${expect})"
}

@test "docker guard: a hybrid MCP is registered when no docker daemon is available" {
  # The e7e7cd40 regression: playwright's fallback no longer matched the old
  # literal, so it was classified docker-only and dropped where the fallback
  # is the whole point.
  _setup '{}'
  _add_docker_mcp_module "hybrid-mod" hybrid
  _stub_docker 1

  run _register_mcp "hybrid-mod"
  assert_success

  refute_output --partial "needs a docker daemon"
  _assert_registered "hybrid-mod" ok
}

@test "docker guard: a docker-only MCP is skipped when no docker daemon is available" {
  _setup '{}'
  _add_docker_mcp_module "dockeronly-mod" plain
  _stub_docker 1

  run _register_mcp "dockeronly-mod"
  assert_success

  assert_output --partial "needs a docker daemon"
  _assert_registered "dockeronly-mod" absent
}

@test "docker guard: a docker-only MCP is registered when a docker daemon is available" {
  _setup '{}'
  _add_docker_mcp_module "dockeronly-mod" plain
  _stub_docker 0

  run _register_mcp "dockeronly-mod"
  assert_success

  refute_output --partial "needs a docker daemon"
  _assert_registered "dockeronly-mod" ok
}

@test "registration: a canonical enabled:false reaches opencode.jsonc" {
  # End-to-end through the real translator + registration with a SHIPPED
  # manifest: the server is wired (present) AND marked disabled, so the user can
  # turn it on from the harness without re-running init.
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/chrome-devtools"
  cp "${PROJECT_ROOT}/src/agentic/chrome-devtools/mcp.json" \
    "${SANDBOX_DIR}/src/agentic/chrome-devtools/mcp.json"

  run _register_mcp "chrome-devtools"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
entry = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {}).get('chrome-devtools')
assert entry is not None, 'chrome-devtools not registered'
assert entry.get('enabled') is False, entry
print('REGISTERED-DISABLED:OK')
"
  assert_success
  grep -qF 'REGISTERED-DISABLED:OK' <<< "$output" || fail "chrome-devtools must register disabled"
}
