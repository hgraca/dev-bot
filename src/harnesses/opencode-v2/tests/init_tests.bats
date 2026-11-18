#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_tests.bats
# Tests init.sh / reset.sh: config seeding, plugin linking, the handover sweep,
# v1 config migration, and the harness gate.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  export V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared"
  export SKIP_CONFIRM=1

  PROJECT="$(mktemp -d)"
  printf '{ "harness": "opencode-v2" }\n' > "${PROJECT}/.devbot.project.jsonc"
  CONFIG="${PROJECT}/opencode.jsonc"
  HELPER="${MODULE_DIR}/lib/v2config.py"
}

teardown() {
  rm -rf "${PROJECT}"
}

v2() {
  python3 "${HELPER}" "$@"
}

@test "init seeds the v2 config shapes" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  [ -f "${CONFIG}" ]
  run v2 has-legacy "${CONFIG}"
  assert_failure
  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "external_directory"'
}

@test "init is byte-idempotent across repeated runs" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local first
  first="$(md5sum "${CONFIG}" | cut -d' ' -f1)"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert_equal "$(md5sum "${CONFIG}" | cut -d' ' -f1)" "${first}"
}

@test "init links each plugin as a directory package" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local name entry
  for name in on-hooks mcp-sync; do
    assert [ -d "${PROJECT}/.opencode/plugins/${name}" ]
    entry="${PROJECT}/.opencode/plugins/${name}/index.ts"
    # MUST be a real file: v2 skips a symlinked plugin entry silently.
    assert [ -f "${entry}" ]
    refute [ -L "${entry}" ]
    grep -q "dev-bot: generated opencode-v2 plugin shim" "${entry}"
    grep -q 'export { default } from ' "${entry}"
  done
}

@test "init leaves auto-loaded plugins out of the config" {
  # v2 auto-loads every directory under .opencode/plugins/. A config entry for
  # one registers the plugin twice and the host fails the second copy with
  # "Duplicate plugin ID", which the TUI reports as a failed plugin.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  run v2 get "${CONFIG}" plugins
  assert_success
  refute_output --partial 'plugins/on-hooks'
  refute_output --partial 'plugins/mcp-sync'
}

@test "init drops config entries for auto-loaded plugins" {
  # A config seeded before the rule changed carries them; init must converge.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/on-hooks" >/dev/null
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/mine" >/dev/null
  v2 upsert-plugin "${CONFIG}" "opencode-some-package@1.2.3" >/dev/null

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run v2 get "${CONFIG}" plugins
  refute_output --partial '.opencode/plugins/'
  assert_output --partial 'opencode-some-package@1.2.3'
}


@test "init leaves root-level module assets alone" {
  # The sweep must only touch the harness-owned farms: .opencode/ root also
  # holds module MCP wrappers, and deleting those breaks them with exit 127.
  mkdir -p "${PROJECT}/.opencode"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/tools-mcp/server/start-tools-mcp.sh" \
    "${PROJECT}/.opencode/tools-mcp-serve.sh"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/tools-mcp-serve.sh" ]
}

@test "init retires the v1 v2/ plugin farm including its nested dir" {
  # A leftover `.opencode/v2/plugins/` (from an earlier layout) must not survive:
  # rmdir is non-recursive, so the parent only goes once the child is gone.
  mkdir -p "${PROJECT}/.opencode/v2/plugins"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  refute [ -d "${PROJECT}/.opencode/v2" ]
}

@test "every plugin directory carries a package.json" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local name
  for name in on-hooks mcp-sync; do
    assert [ -f "${PROJECT}/.opencode/plugins/${name}/package.json" ]
    python3 -c "
import json,sys
d=json.load(open('${PROJECT}/.opencode/plugins/${name}/package.json'))
assert d['name'].startswith('devbot-'), d
assert 'exports' in d, d
"
  done
}

@test "init retires the pty package an earlier build linked" {
  # The PTY extension is no longer shipped: required-plugins.jsonc dropped it, so
  # a stale shim package has to be removed or the host keeps auto-loading it.
  local dir="${PROJECT}/.opencode/plugins/pty"
  mkdir -p "${dir}"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${dir}/index.ts"
  printf '{"name":"devbot-pty","version":"0.0.0","type":"module","main":"./index.ts","exports":{".":"./index.ts"}}\n' > "${dir}/package.json"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${dir}" ]
}

@test "init drops a bun-pty dependency it recorded as its own" {
  # The retired PTY extension was its only consumer. The ownership record is what
  # keeps the edit from touching a dependency the project declared.
  mkdir -p "${PROJECT}/.opencode"
  printf '{ "dependencies": { "bun-pty": "^0.4.10" } }\n' > "${PROJECT}/.opencode/package.json"
  printf 'bun-pty\n' > "${PROJECT}/.opencode/.devbot-managed-deps"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "Dropped bun-pty"

  run python3 -c "import json; print(json.load(open('${PROJECT}/.opencode/package.json')).get('dependencies', {}))"
  refute_output --partial "bun-pty"
  [ ! -e "${PROJECT}/.opencode/.devbot-managed-deps" ]
}

@test "a package.json the project already had is not claimed" {
  mkdir -p "${PROJECT}/.opencode"
  printf '{ "dependencies": { "bun-pty": "^0.4.10" } }\n' > "${PROJECT}/.opencode/package.json"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/.devbot-managed-deps" ]
  run python3 -c "import json; print(json.load(open('${PROJECT}/.opencode/package.json')).get('dependencies', {}))"
  assert_output --partial "bun-pty"
}

@test "init pins local MCP servers to the project directory" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # A local server carried over from a migrated v1 config has no cwd, and v2
  # spawns it outside the project — its relative wrapper path then exits 127.
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["bash","x.sh"]}'

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run python3 "${MODULE_DIR}/lib/v2config.py" get "${CONFIG}" mcp.servers.demo.cwd
  assert_success
  assert_output --partial "${PROJECT}"
}

@test "init sweeps a dev-bot symlink and keeps user files" {
  mkdir -p "${PROJECT}/.opencode/plugins"
  # A target that does not exist: readlink -f cannot resolve it.
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards/hooks/opencode/gone.ts" "${PROJECT}/.opencode/plugins/gone.ts"
  echo user > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/plugins/gone.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init drops the emptied v1 plugin farms" {
  mkdir -p "${PROJECT}/.opencode/tui-plugins"
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/pty-monitor" "${PROJECT}/.opencode/tui-plugins/pty-monitor"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  refute [ -d "${PROJECT}/.opencode/tui-plugins" ]
}

@test "init retires the v1 TUI plugin list and keeps the rest" {
  # opencode 2.3 still applies a project tui.json. Its v1 seed re-declared
  # opencode-tabs@0.3.0 (rejected by 2.3's TUI module validator) and three
  # ./tui-plugins/* paths this harness no longer links.
  mkdir -p "${PROJECT}/.opencode"
  cat > "${PROJECT}/.opencode/tui.json" <<'EOF'
{
  "$schema": "https://opencode.ai/tui.json",
  "plugin_enabled": { "internal:sidebar-context": false },
  "plugin": [
    "opencode-tabs@0.3.0",
    "./tui-plugins/pty-monitor/index.ts",
    "./tui-plugins/tui-defaults/index.ts",
    "./tui-plugins/provider-ttft/index.ts",
    "opencode-mine@1.0.0"
  ]
}
EOF

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${PROJECT}/.opencode/tui.json" plugin
  refute_output --partial 'opencode-tabs'
  refute_output --partial 'tui-plugins'
  assert_output --partial 'opencode-mine@1.0.0'
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${PROJECT}/.opencode/tui.json" plugin_enabled
  assert_output --partial 'internal:sidebar-context'
}

@test "init migrates a v1 config and leaves a backup" {
  git -C "${PROJECT}" init -q
  cat > "${CONFIG}" <<'EOF'
{
  "model": "p/m",
  "plugin": ["a-plugin", ["./x.ts", {"k": 1}], ".opencode/plugins/on-hooks.ts", "opencode-pty@0.3.6"],
  "permission": {"bash": {"*": "allow", "sudo *": "ask"}, "edit": "allow", "list": "allow"},
  "agent": {"devbot": {"model": "p/m", "variant": "high"}, "plan": {"disable": true}},
  "provider": {"p": {"npm": "@x/y", "options": {"t": 1}}},
  "mcp": {"s": {"type": "local", "command": ["c"], "enabled": false}},
  "lsp": true
}
EOF
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success

  assert [ -f "${CONFIG}.pre-v2.bak" ]
  # The backup must not linger as an untracked file in the consumer's repo.
  run git -C "${PROJECT}" check-ignore -v opencode.jsonc.pre-v2.bak
  assert_success
  assert_output --partial "opencode.jsonc.pre-v2.bak"
  run grep -c "DEVBOT - config backup" "${PROJECT}/.gitignore"
  assert_output "2"
  run v2 has-legacy "${CONFIG}"
  assert_failure

  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "shell"'
  assert_output --partial '"resource": "sudo *"'
  refute_output --partial '"action": "list"'

  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"disabled": true'
  refute_output --partial '"enabled"'

  run v2 get "${CONFIG}" agents
  assert_output --partial '"model": "p/m#high"'
  assert_output --partial '"disabled": true'

  run v2 get "${CONFIG}" providers
  assert_output --partial '"package": "@x/y"'
  assert_output --partial '"settings"'
}

@test "reset removes dev-bot symlinks and keeps user files" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # .opencode/agents is a delegated symlink, so plant the link in the
  # plugin dir — a real directory that reset walks.
  mkdir -p "${PROJECT}/.opencode/plugins"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards" "${PROJECT}/.opencode/plugins/guards"
  echo user > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  refute [ -e "${PROJECT}/.opencode/plugins/guards" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "reset leaves the tree untouched when opencode-v2 is not selected" {
  printf '{ "harness": "opencode" }\n' > "${PROJECT}/.devbot.project.jsonc"
  mkdir -p "${PROJECT}/.opencode/agents"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/guards" "${PROJECT}/.opencode/agents/guards"

  run bash "${MODULE_DIR}/reset.sh" "${PROJECT}"
  assert_success
  assert [ -L "${PROJECT}/.opencode/agents/guards" ]
}

@test "reset keeps a user's broken symlink" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins"
  ln -sfn "/nonexistent/user-target" "${PROJECT}/.opencode/plugins/mine"

  bash "${MODULE_DIR}/reset.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/plugins/mine" ]
}

@test "init keeps a user's own plugin entry file" {
  mkdir -p "${PROJECT}/.opencode/plugins/tui-defaults"
  printf 'export default {}\n' > "${PROJECT}/.opencode/plugins/tui-defaults/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run cat "${PROJECT}/.opencode/plugins/tui-defaults/index.ts"
  assert_output "export default {}"
}

@test "a v1-only plugin does not suppress the module's MCP under v2" {
  # codebase-index ships plugin.opencode.json only; that plugin does not load
  # under 2.x, so its canonical MCP must be registered instead.
  local cfg
  cfg="$(mktemp)"
  printf '{"codebase_index_provider": "codebase-index"}\n' > "${cfg}"

  DEV_BOT_GLOBAL_CONFIG="${cfg}" bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run v2 get "${CONFIG}" mcp
  assert_success
  assert_output --partial '"codebase-index"'
  rm -f "${cfg}"
}

@test "init links no TUI part at all" {
  # tui-defaults is still on the pre-2.3 API (its kv surface has no 2.3
  # equivalent), and provider-ttft was retired once 2.3's built-in prompt footer
  # started reporting ttft. This harness ships server plugins only.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/tui-defaults" ]
  [ ! -e "${PROJECT}/.opencode/plugins/provider-ttft" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "tui-defaults"
  refute_output --partial "provider-ttft"
}

@test "init retires the TTFT package an earlier build shipped" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins/provider-ttft"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    "export { default } from \"/nope\"" > "${PROJECT}/.opencode/plugins/provider-ttft/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/provider-ttft" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "provider-ttft"
}

@test "init retires a plugin package this build no longer ships" {
  # An earlier init generated it (marker present) and listed it in the config.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins/old-plugin"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    "export { default } from \"/nope\"" > "${PROJECT}/.opencode/plugins/old-plugin/index.ts"
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/old-plugin" >/dev/null

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  [ ! -e "${PROJECT}/.opencode/plugins/old-plugin" ]
  run v2 get "${CONFIG}" plugins
  refute_output --partial "old-plugin"
}

@test "init keeps a user's own plugin package" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  printf 'export default { id: "mine", setup() {} }\n' \
    > "${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${PROJECT}/.opencode/plugins/mine/index.ts" ]
}

@test "init removes the v1 harness's plugin links" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  ln -sfn "${DEV_BOT_ROOT}/src/harnesses/opencode/hooks/on-hooks.ts" \
    "${PROJECT}/.opencode/plugins/on-hooks.ts"
  printf 'export default {}\n' > "${PROJECT}/.opencode/plugins/mine.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ ! -e "${PROJECT}/.opencode/plugins/on-hooks.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init never removes through a symlinked plugin directory" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local outside
  outside="$(mktemp -d)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" \
    > "${outside}/index.ts"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/elsewhere"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -f "${outside}/index.ts" ]
  rm -r -f "${outside}"
}

@test "init never treats a symlinked entry file as a generated package" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local outside
  outside="$(mktemp)"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${outside}"
  mkdir -p "${PROJECT}/.opencode/plugins/mine"
  ln -sfn "${outside}" "${PROJECT}/.opencode/plugins/mine/index.ts"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -d "${PROJECT}/.opencode/plugins/mine" ]
  assert [ -f "${outside}" ]
  rm -f "${outside}"
}

# ── Skill farm wiring (audit-01 FAIL-4) ───────────────────────────────────────
# A 2.x host scans ONLY <.opencode/skill(s)>; it never discovers <devbot_dir>/
# skills. The farm therefore has to be linked into .opencode/skills, one link per
# farm entry, or every devbot skill is unloadable.

@test "init wires the skill farm into .opencode/skills, one link per entry" {
  mkdir -p "${PROJECT}/.agents/skills/devbot/git/devbot:git-commits"
  printf -- '---\nname: devbot:git-commits\n---\n' \
    > "${PROJECT}/.agents/skills/devbot/git/devbot:git-commits/SKILL.md"
  mkdir -p "${PROJECT}/.agents/skills/mattpocock-grilling"
  printf -- '---\nname: grilling\n---\n' > "${PROJECT}/.agents/skills/mattpocock-grilling/SKILL.md"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  # Each farm entry is reachable through the directory the host scans.
  assert [ -L "${PROJECT}/.opencode/skills/devbot" ]
  [ "$(readlink "${PROJECT}/.opencode/skills/devbot")" = "${PROJECT}/.agents/skills/devbot" ]
  assert [ -L "${PROJECT}/.opencode/skills/mattpocock-grilling" ]
  # The id a 2.x host derives is the SKILL.md parent directory: devbot:<skill>.
  assert [ -f "${PROJECT}/.opencode/skills/devbot/git/devbot:git-commits/SKILL.md" ]
}

@test "_link_skill_farm leaves a module-authored link that points outside the farm" {
  # `.opencode/skills/signoz` is wired by the signoz module itself, to its
  # generated skills under storage/. The farm reconcile owns only links into
  # <devbot_dir>/skills, so it must not remove this one.
  mkdir -p "${PROJECT}/.agents/skills/devbot"
  mkdir -p "${PROJECT}/.opencode/skills"
  ln -sfn "${DEV_BOT_ROOT}/storage/signoz/skills" "${PROJECT}/.opencode/skills/signoz"

  run bash -c '
    set -euo pipefail
    _ok() { :; }; _warn() { :; }; _skip() { :; }
    _devbot_get_project_dir() { printf ".agents"; }
    OPENCODE_DIR="${1}/.opencode"
    eval "$(sed -n "\|^_link_skill_farm() {\$|,\|^}\$|p" "${2}")"
    _link_skill_farm "${1}"
  ' _ "${PROJECT}" "${MODULE_DIR}/init.sh"
  assert_success

  assert [ -L "${PROJECT}/.opencode/skills/signoz" ]
}

@test "init prunes a farm link whose entry disappeared" {
  mkdir -p "${PROJECT}/.agents/skills/devbot"
  mkdir -p "${PROJECT}/.agents/skills/gone"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert [ -L "${PROJECT}/.opencode/skills/gone" ]

  rm -r -f "${PROJECT}/.agents/skills/gone"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ ! -e "${PROJECT}/.opencode/skills/gone" ]
}


@test "init keeps a farm entry whose target lives under dev-bot (external modules)" {
  # External-module skills enter the farm as links into the vendored source
  # (vendor/<vendor>/<repo>/skills), so their .opencode/skills link RESOLVES under
  # DEV_BOT_ROOT. The handover sweep and the declared-asset pruner both treat a
  # link resolving under dev-bot as a stale asset, which deleted every external
  # module skill on each reinit.
  mkdir -p "${PROJECT}/.agents/skills"
  ln -sfn "${DEV_BOT_ROOT}/src/agentic/git/skills" "${PROJECT}/.agents/skills/probe-external"

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  assert [ -L "${PROJECT}/.opencode/skills/probe-external" ]
  # And the skill behind it is reachable: the id is the SKILL.md parent directory.
  assert [ -f "${PROJECT}/.opencode/skills/probe-external/git-commits/SKILL.md" ]
}


# ── Nested projects: one copy per plugin id ───────────────────────────────────
# A v2 host discovers every ancestor's `.opencode/plugins/` package, so a dev-bot
# project nested inside another dev-bot project loads two copies of each plugin.
# The host keeps the first and fails the second with "Duplicate plugin ID", which
# the TUI shows as a failed plugin. The ancestor's copy is location-scoped, so it
# serves the nested project too; the nested init must not write a duplicate.

_nested_projects() {
  PARENT="${PROJECT}/parent"
  CHILD="${PARENT}/child"
  mkdir -p "${CHILD}"
  printf '{ "harness": "opencode-v2" }\n' > "${PARENT}/.devbot.project.jsonc"
  printf '{ "harness": "opencode-v2" }\n' > "${CHILD}/.devbot.project.jsonc"
}

# _ancestor_package <name> <target> [marker 0|1] [manifest name]
# Hand-writes a plugin package so a test can vary one detection guard at a time.
# The manifest is compact on purpose: init must not depend on its formatting.
_ancestor_package() {
  local name="$1" target="$2" marker="${3:-1}"
  local manifest="${4:-devbot-${name}}"
  local dir="${PARENT}/.opencode/plugins/${name}"
  mkdir -p "${dir}"
  if [[ "${marker}" == "1" ]]; then
    printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${dir}/index.ts"
  else
    printf '%s\n' "// hand-written by the project" > "${dir}/index.ts"
  fi
  printf 'export { default } from "%s"\n' "${target}" >> "${dir}/index.ts"
  printf '{"name":"%s","version":"0.0.0","type":"module","exports":{".":"./index.ts"}}\n' \
    "${manifest}" > "${dir}/package.json"
}

@test "init does not duplicate a plugin an ancestor project already supplies" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  local name
  for name in on-hooks mcp-sync; do
    assert [ -d "${PARENT}/.opencode/plugins/${name}" ]
    refute [ -e "${CHILD}/.opencode/plugins/${name}" ]
  done
}

@test "init removes its own plugin copies once an ancestor supplies them" {
  # The historical shape: the nested project was initialised first, so it owns a
  # copy of every plugin before the ancestor is initialised.
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null
  assert [ -d "${CHILD}/.opencode/plugins/on-hooks" ]

  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  local name
  for name in on-hooks mcp-sync; do
    refute [ -e "${CHILD}/.opencode/plugins/${name}" ]
    # The ancestor keeps the only copy.
    assert [ -d "${PARENT}/.opencode/plugins/${name}" ]
  done
}

@test "an ancestor shim without the dev-bot marker does not count as supplying" {
  _nested_projects
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  _ancestor_package on-hooks "${target}" 0
  # Pin the fixture: the marker is the only guard failing here.
  grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-on-hooks"' "${PARENT}/.opencode/plugins/on-hooks/package.json"
  refute grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "an ancestor package with another manifest name does not count as supplying" {
  _nested_projects
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  _ancestor_package on-hooks "${target}" 1 someone-elses-plugin
  # Pin the fixture: the manifest name is the only guard failing here.
  grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"
  grep -qE '"name":"someone-elses-plugin"' "${PARENT}/.opencode/plugins/on-hooks/package.json"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "an ancestor shim whose target is gone does not suppress this project's copy" {
  # A moved or deleted toolkit checkout leaves a package that cannot import, so it
  # holds no plugin id and the nested project must still write its own copy.
  _nested_projects
  _ancestor_package on-hooks "${PROJECT}/gone/on-hooks.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "which is gone"

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "dev-bot: generated opencode-v2 plugin shim" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
}

@test "init warns when an ancestor supplies a different dev-bot build" {
  # The host loads the ancestor's copy first, so the nested project follows that
  # build; init still has to say so instead of silently changing version.
  _nested_projects
  local other="${PROJECT}/other-dev-bot/src/hooks"
  mkdir -p "${other}"
  printf 'export default { id: "devbot-hooks", setup() {} }\n' > "${other}/on-hooks.ts"
  _ancestor_package on-hooks "${other}/on-hooks.ts"
  assert [ -f "${PARENT}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "generated opencode-v2 plugin shim" "${PARENT}/.opencode/plugins/on-hooks/index.ts"
  grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-on-hooks"' "${PARENT}/.opencode/plugins/on-hooks/package.json"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "runs a different dev-bot build"
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "a symlinked spelling of the same build is not reported as different" {
  # The same checkout reached through a symlinked directory must not warn: a
  # string compare would, because the shim records the spelling used at its init.
  _nested_projects
  local link="${PROJECT}/dev-bot-shortcut"
  ln -s "${DEV_BOT_ROOT}" "${link}"
  _ancestor_package on-hooks "${link}/src/harnesses/opencode-v2/hooks/on-hooks.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  refute_output --partial "runs a different dev-bot build"
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "init leaves a user's package alone when an ancestor supplies the plugin" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  mkdir -p "${CHILD}/.opencode/plugins/on-hooks"
  printf 'export default { id: "my-own-on-hooks" }\n' > "${CHILD}/.opencode/plugins/on-hooks/index.ts"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  assert_output --partial "duplicate registration may persist"

  assert [ -f "${CHILD}/.opencode/plugins/on-hooks/index.ts" ]
  grep -q "my-own-on-hooks" "${CHILD}/.opencode/plugins/on-hooks/index.ts"
  # The ancestor keeps its own copy untouched too.
  assert [ -f "${PARENT}/.opencode/plugins/on-hooks/index.ts" ]
}

@test "init never removes a symlinked plugin directory shadowing an ancestor's copy" {
  _nested_projects
  bash "${MODULE_DIR}/init.sh" "${PARENT}" >/dev/null
  mkdir -p "${PROJECT}/outside/on-hooks"
  printf 'export default { id: "outside-on-hooks" }\n' > "${PROJECT}/outside/on-hooks/index.ts"
  mkdir -p "${CHILD}/.opencode/plugins"
  ln -sfn "${PROJECT}/outside/on-hooks" "${CHILD}/.opencode/plugins/on-hooks"

  bash "${MODULE_DIR}/init.sh" "${CHILD}" >/dev/null

  assert [ -L "${CHILD}/.opencode/plugins/on-hooks" ]
  assert [ -f "${PROJECT}/outside/on-hooks/index.ts" ]
}

@test "a huge ancestor shim does not abort init on a broken pipe" {
  # `sed | head` stops reading at the first match; a long shim then makes sed
  # take SIGPIPE, and pipefail would surface 141 as a failed init.
  _nested_projects
  local dir="${PARENT}/.opencode/plugins/on-hooks"
  local target="${DEV_BOT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  mkdir -p "${dir}"
  printf '%s\n' "// dev-bot: generated opencode-v2 plugin shim (do not edit)" > "${dir}/index.ts"
  local i
  for ((i = 0; i < 2000; i++)); do
    printf 'export { default } from "%s"\n' "${target}" >> "${dir}/index.ts"
  done
  printf '{"name":"devbot-on-hooks","version":"0.0.0","type":"module","exports":{".":"./index.ts"}}\n' > "${dir}/package.json"

  run bash "${MODULE_DIR}/init.sh" "${CHILD}"
  assert_success
  refute [ -e "${CHILD}/.opencode/plugins/on-hooks" ]
}

@test "a project with no ancestor dev-bot plugins still gets every plugin" {
  # The nesting guard must not suppress the normal, non-nested install.
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success

  local name
  for name in on-hooks mcp-sync; do
    assert [ -d "${PROJECT}/.opencode/plugins/${name}" ]
  done
}

# ── Modules this harness provides natively ───────────────────────────────────
# OpenCode 2.x ships its own websearch tool, so the devbot module would only add
# a duplicate MCP server (one tool, plus its schema and instruction block in
# every session). The exclusion is unconditional — the module's enabled flag
# cannot bring it back — and reinit says why, once.

@test "websearch: not registered when the module is enabled" {
  printf '{ "harness": "opencode-v2", "modules": { "websearch": true } }\n' > "${PROJECT}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "built-in websearch tool"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: not registered when the module is disabled either" {
  # The ignore is unconditional, not a consequence of enablement: no config
  # flip may re-enable it on this harness.
  printf '{ "harness": "opencode-v2", "modules": { "websearch": false } }\n' > "${PROJECT}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "built-in websearch tool"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: an entry an earlier init wrote is removed" {
  # merge-mcp is add-only, so an existing entry survives registration; the
  # exclusion has to retire it or the duplicate server stays live. Seed it the
  # way an earlier devbot would have: config first, then the entry.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # The module's own URL is what makes the entry dev-bot's rather than the
  # project's, so seed exactly that (the ownership test below covers the other
  # case).
  local canonical_url
  canonical_url="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/src/agentic/websearch/mcp.json" mcp websearch url)"
  v2 merge-mcp "${CONFIG}" websearch "{\"type\":\"remote\",\"url\":\"${canonical_url}\"}"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "removed the MCP entry this harness provides natively"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: a server the project configured itself survives" {
  # Ownership is decided on the module's own URL: a project may run its own MCP
  # service under that name, and deleting it on every reinit would be worse than
  # the duplicate this exclusion removes.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  v2 merge-mcp "${CONFIG}" websearch '{"type":"remote","url":"https://search.example.test/mcp"}'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "left your own 'websearch' MCP server in place"

  run v2 get "${CONFIG}" "mcp.servers.websearch.url"
  assert_output --partial "search.example.test"
}

@test "websearch: the notice is printed once per run" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  [ "$(printf '%s\n' "${output}" | grep -c 'built-in websearch tool')" -eq 1 ]
}

@test "websearch: the exclusion is a list, not a blanket MCP skip" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  # A module this harness does not provide natively is still registered.
  run v2 get "${CONFIG}" "mcp.servers"
  assert_output --partial "devbot-tools"
  refute_output --partial "websearch"
}
