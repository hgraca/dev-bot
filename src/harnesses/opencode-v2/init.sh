#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode-v2/init.sh
# Sets up OpenCode 2.x in a project: copies the .opencode/ template directory,
# writes opencode.jsonc from the dist template, links plugin directories under
# .opencode/v2/plugins/, registers MCP servers under mcp.servers, and delegates
# the agents/commands/tools/skills farms to the devbot dir.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Defaulted BEFORE anything sources _shared through it — a caller that has not
# exported DEV_BOT_ROOT (a clean shell, a test that sources this file) must not
# die on `set -u`.
#
# Located by walking up until src/_shared is found rather than assuming three
# levels: the checkout puts it at src/harnesses/<name>, while a test harness
# plants this script at the root of a fake install. The wrapper above only sets
# DEV_BOT_ROOT as a side effect, which is what made the ordering load-bearing.
if [[ -z "${DEV_BOT_ROOT:-}" ]]; then
  _devbot_root_candidate="${MODULE_DIR}"
  for _devbot_root_hop in 0 1 2 3 4 5; do
    if [[ -f "${_devbot_root_candidate}/src/_shared/functions.sh" ]]; then
      DEV_BOT_ROOT="${_devbot_root_candidate}"
      break
    fi
    _devbot_root_candidate="$(cd "${_devbot_root_candidate}/.." && pwd)"
  done
  unset _devbot_root_candidate _devbot_root_hop
fi
if [[ -z "${DEV_BOT_ROOT:-}" ]]; then
  echo "FATAL: cannot locate the dev-bot root (no src/_shared beside this script); set DEV_BOT_ROOT" >&2
  exit 1
fi
export DEV_BOT_ROOT

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

# shellcheck source=../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Paths ──────────────────────────────────────────────────────────────────────

OPENCODE_TPL="${MODULE_DIR}/_opencode-v2.tpl"
DIST_CONFIG="${MODULE_DIR}/opencode-v2.dist.jsonc"
V2HELPER="${MODULE_DIR}/lib/v2config.py"
OPENCODE_DIR="${PROJECT_DIR}/.opencode"
# V2 resolves configured local plugin paths ONLY under .opencode/plugins/ — a
# path in any other directory is skipped silently, with no log line. Both
# harnesses therefore share this directory, and isolation comes from the sweep
# below: whichever harness initialises removes the other's dev-bot-owned links.
V2_PLUGIN_DIR="${OPENCODE_DIR}/plugins"
CONFIG="${PROJECT_DIR}/opencode.jsonc"

# Config edits for the v2 shapes. The shared helpers under src/_shared write the
# v1 keys, so this module owns its own.
_v2() {
  V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared" python3 "${V2HELPER}" "$@"
}

# Marks the generated shim files so a later sweep can tell dev-bot's own plugin
# directories from a user's.
_PLUGIN_SHIM_MARKER="// dev-bot: generated opencode-v2 plugin shim (do not edit)"

# ── Record a dependency dev-bot added to .opencode/ ───────────────────────────
# .opencode/package.json is seeded once and then the project's own, so deleting an
# entry by name alone could remove a dependency the project needs. This file is
# the ownership record: a name in it was put there by dev-bot, and this harness
# may retire exactly those. Earlier builds wrote it for `bun-pty`; no dependency
# is installed today, but the record is still read when a retired one is dropped.
_MANAGED_DEPS_FILE=".devbot-managed-deps"

# ── Merge .opencode/ template directory ───────────────────────────────────────
_copy_opencode_dir() {
  if [[ ! -d "${OPENCODE_TPL}" ]]; then
    _warn "Template directory not found at ${OPENCODE_TPL}"
    return 1
  fi

  local copied=0
  mkdir -p "${OPENCODE_DIR}"

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#${OPENCODE_TPL}/}"
    local tgt="${OPENCODE_DIR}/${rel}"

    # `continue`, never `return`: find emits directories before their contents,
    # so returning on the first .gitkeep aborts the copy of every later dir.
    [[ "$(basename "${rel}")" == ".gitkeep" ]] && continue

    if [[ -e "${tgt}" ]]; then
      _skip "${rel} already exists"
    else
      mkdir -p "$(dirname "${tgt}")"
      cp -r "${src_file}" "${tgt}"
      _ok "${rel} copied"
      copied=$((copied + 1))
    fi
  done < <(find "${OPENCODE_TPL}" -mindepth 1 -print0 2>/dev/null)

  if [[ ${copied} -eq 0 ]]; then
    _skip "no new files from template"
  fi
}

# ── Remove .gitkeep files ──────────────────────────────────────────────────────
_remove_gitkeep_files() {
  local count=0
  while IFS= read -r -d '' f; do
    rm -f "$f"
    count=$((count + 1))
  done < <(find "${OPENCODE_DIR}" -name '.gitkeep' -type f -print0 2>/dev/null)
  if [[ ${count} -gt 0 ]]; then _ok "Removed ${count} .gitkeep file(s) from .opencode/"; fi
}

# ── Write a runtime JSONC config from a dist template ──────────────────────────
# One-shot seed: an existing target is user-owned and left alone. Comments are
# stripped string-aware (so URLs survive) and __GPU_ENABLED__ /
# __DEV_BOT_ROOT__ substituted.
_write_jsonc_from_dist() {
  local dist="$1"
  local config="$2"
  local name
  name="$(basename "${config}")"

  if [[ -f "${config}" ]]; then
    _skip "${name} already exists"
    return 0
  fi

  if [[ ! -f "${dist}" ]]; then
    _warn "Template not found at ${dist}"
    return 1
  fi

  _info "Writing ${name}..."

  GPU_ENABLED="${GPU_ENABLED:-false}" DEV_BOT_ROOT="${DEV_BOT_ROOT:-}" \
    DIST_CONFIG="${dist}" CONFIG="${config}" python3 - <<'PY'
import os
import tempfile
raw = open(os.environ["DIST_CONFIG"]).read()

out = []
i, n = 0, len(raw)
while i < n:
    if raw[i] == '"':                      # string literal — copy verbatim
        j = i + 1
        while j < n:
            if raw[j] == "\\":
                j += 2
            elif raw[j] == '"':
                j += 1
                break
            else:
                j += 1
        out.append(raw[i:j])
        i = j
        continue
    if raw[i : i + 2] == "//":             # line comment
        j = raw.find("\n", i)
        if j == -1:
            break
        i = j
        continue
    if raw[i : i + 2] == "/*":             # block comment
        j = raw.find("*/", i + 2)
        if j == -1:
            break
        i = j + 2
        continue
    out.append(raw[i])
    i += 1

stripped = "".join(out).replace("__GPU_ENABLED__", os.environ["GPU_ENABLED"]).replace(
    "__DEV_BOT_ROOT__", os.environ.get("DEV_BOT_ROOT", "")
)
lines = [line.rstrip() for line in stripped.splitlines() if line.strip()]
data = "\n".join(lines) + "\n"
fd, tmp = tempfile.mkstemp(
    dir=os.path.dirname(os.environ["CONFIG"]),
    prefix="." + os.path.basename(os.environ["CONFIG"]) + ".",
)
with os.fdopen(fd, "w") as f:
    f.write(data)
umask = os.umask(0)
os.umask(umask)
os.chmod(tmp, 0o644 & ~umask)
os.replace(tmp, os.environ["CONFIG"])
PY
  _ok "${name} written"
}

_write_opencode_config() {
  GPU_ENABLED="$(_qmd_gpu_value)" \
    _write_jsonc_from_dist "${DIST_CONFIG}" "${CONFIG}"
}

# ── Retire the bun-pty dependency an earlier build declared ──────────────────
# The v2 PTY extension was this adapter's only consumer of `bun-pty`; the plugin
# is gone, so the dependency is dead weight (and a host that installs the config
# directory's dependencies would fetch it again). `.opencode/package.json` is
# seeded once and then the project's own, so the entry is dropped only when the
# harness's ownership record names it — a dependency the project declared is
# never touched.
_retire_pty_dependency() {
  local manifest="${OPENCODE_DIR}/package.json"
  local owned="${OPENCODE_DIR}/${_MANAGED_DEPS_FILE}"
  [[ -f "${manifest}" && -f "${owned}" ]] || return 0
  grep -qxF "bun-pty" "${owned}" 2>/dev/null || return 0

  local dropped
  dropped="$(python3 - "${manifest}" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
deps = data.get("dependencies")
if not isinstance(deps, dict) or "bun-pty" not in deps:
    sys.exit(0)
del deps["bun-pty"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("bun-pty")
PYEOF
)"

  [[ -n "${dropped}" ]] || return 0
  if grep -vxF "bun-pty" "${owned}" > "${owned}.tmp" 2>/dev/null; then :; fi
  if [[ -s "${owned}.tmp" ]]; then mv "${owned}.tmp" "${owned}"; else rm -f "${owned}" "${owned}.tmp"; fi
  _ok "Dropped bun-pty from .opencode/package.json — no shipped plugin uses it"
}

# ── Migrate a v1-shaped config ────────────────────────────────────────────────
# Both harnesses read the SAME filename, so a project that once ran the v1
# adapter already has opencode.jsonc. The seed above skips it, and registering
# v2 keys into a v1 document would produce a config that is neither. Convert it
# once — with a backup beside it — rather than refusing.
_migrate_legacy_config() {
  [[ -f "${CONFIG}" ]] || return 0
  local legacy
  legacy="$(_v2 has-legacy "${CONFIG}" 2>/dev/null || true)"
  [[ -n "${legacy}" ]] || return 0

  _info "Migrating OpenCode 1.x config keys (${legacy})..."
  local out rc=0
  out="$(V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared" \
    python3 "${MODULE_DIR}/lib/migrate_v1.py" "${CONFIG}" \
    --backup "${CONFIG}.pre-v2.bak" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    _fatal "config migration failed — the original is untouched:"
    printf '%s\n' "${out}" >&2
    return 1
  fi

  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] && _ok "  ${line}"
  done <<<"${out}"
  _ok "opencode.jsonc migrated to the v2 shapes"

  # The backup is a one-time recovery artifact, not project source. Ignore it so
  # the migration does not leave a permanent untracked file in every consumer
  # repo (audit-03 N2); the file itself stays on disk for the user.
  local backup
  backup="$(basename "${CONFIG}").pre-v2.bak"
  if [[ -f "${PROJECT_DIR}/${backup}" ]] &&
    git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _upsert_gitignore_section "${PROJECT_DIR}/.gitignore" \
      "# >>> DEVBOT - config backup" \
      "# <<< DEVBOT - config backup" \
      "${backup}" >/dev/null 2>&1 || true
  fi
}

# ── Hand over from a previously selected harness ──────────────────────────────
# The unselected harness's reset is skipped by design, so its symlinks survive in
# .opencode/ and this host would auto-load them from .opencode/plugins/. Remove
# ONLY links resolving under DEV_BOT_ROOT: user files, opencode's own
# .opencode/opencode.json and anything else are never touched.
_sweep_foreign_artifacts() {
  [[ -d "${OPENCODE_DIR}" ]] || return 0

  # Scope: the harness-owned farms only. `.opencode/` at the root also holds
  # module-authored assets (`tools-mcp-serve.sh`, `*-serve.mcp.sh`, wrapper .js)
  # that are symlinks into dev-bot too — sweeping those breaks their MCP servers
  # with exit 127.
  #
  # A link into the project's own skill farm is never foreign, even though its
  # target resolves on into dev-bot's vendored sources: `_link_skill_farm` owns
  # those (audit-01 FAIL-4). Without this the sweep deleted every farm entry at
  # the start of each init and the farm had to be rebuilt from scratch.
  local removed=0 link target resolved candidate farm
  local farm_dir
  farm_dir="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/skills"
  for farm in plugins plugin tui-plugins agents commands tools skills; do
    [[ -d "${OPENCODE_DIR}/${farm}" ]] || continue
  while IFS= read -r -d '' link; do
    target="$(readlink "${link}" 2>/dev/null || true)"
    [[ -n "${target}" ]] || continue
    local direct
    direct="$(_devbot_link_direct_target "${link}")"
    [[ -n "${direct}" && "${direct}" == "${farm_dir}"/* ]] && continue
    resolved="$(readlink -f "${link}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]]; then
      # A dev-bot link whose source moved or was removed still has to go, and
      # readlink -f reports nothing for a missing target — normalise it by hand.
      if [[ "${target}" == /* ]]; then
        candidate="${target}"
      else
        candidate="$(dirname "${link}")/${target}"
      fi
      resolved="$(realpath -m "${candidate}" 2>/dev/null || printf '%s' "${candidate}")"
    fi
    [[ -n "${resolved}" && "${resolved}" == "${DEV_BOT_ROOT}"/* ]] || continue
    rm -f "${link}"
    removed=$((removed + 1))
  done < <(find "${OPENCODE_DIR}/${farm}" -type l -print0 2>/dev/null)
  done

  # Drop the v1-only plugin farms once they are empty; a user's own files keep
  # the directory alive.
  # v1's TUI farm is gone for good; plugins/ is rebuilt by this harness below.
  # `rmdir` is non-recursive, so the retired `v2/plugins/` must be removed before
  # its parent — otherwise the parent silently survives every reinit and the
  # tree keeps advertising a farm this harness no longer uses (audit-03 N3).
  local dir
  for dir in "${OPENCODE_DIR}/v2/plugins" "${OPENCODE_DIR}/tui-plugins" "${OPENCODE_DIR}/v2"; do
    [[ -d "${dir}" ]] && rmdir "${dir}" 2>/dev/null || true
  done

  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} symlink(s) left by a previously selected harness"
  fi
  return 0
}

# ── A plugin package an ancestor project already supplies ─────────────────────
# A v2 host discovers configuration from the current directory and EVERY ancestor
# through the filesystem root, and auto-loads each discovered
# `.opencode/plugins/` package. A dev-bot project nested inside another dev-bot
# project therefore sees the ancestor's copies of these plugins beside its own;
# the host keeps the first and fails the second with "Duplicate plugin ID",
# which the TUI reports as a failed plugin.
#
# The ancestor's instance is location-scoped — its `setup(ctx)` runs for the
# session's location — so it serves this project too. Since the host loads that
# copy first regardless, writing our own only adds the failed entry: this project
# follows the ancestor's toolkit version, and init warns when that differs.
# Identify a dev-bot package by the generated manifest's name plus the shim
# marker; a user's own package of the same directory name never matches.
_ancestor_plugin_dir() {
  local name="$1"
  local dir parent candidate
  dir="${PROJECT_DIR}"
  while :; do
    parent="$(dirname "${dir}")"
    [[ "${parent}" == "${dir}" ]] && return 1
    dir="${parent}"
    candidate="${dir}/.opencode/plugins/${name}"
    [[ -d "${candidate}" && ! -L "${candidate}" ]] || continue
    [[ -f "${candidate}/index.ts" && ! -L "${candidate}/index.ts" ]] || continue
    grep -qF "${_PLUGIN_SHIM_MARKER}" "${candidate}/index.ts" 2>/dev/null || continue
    grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-'"${name}"'"' "${candidate}/package.json" 2>/dev/null || continue
    printf '%s\n' "${candidate}"
    return 0
  done
}

# Remove this project's generated copy of a plugin an ancestor supplies. Returns
# 1 (and changes nothing) when the entry is not a package this harness wrote: a
# user's package, a symlinked directory or a symlinked entry.
_retire_shadowed_plugin_dir() {
  local dir="$1" name="$2"
  [[ -e "${dir}" || -L "${dir}" ]] || return 0
  if [[ ! -d "${dir}" || -L "${dir}" ]]; then return 1; fi
  if [[ ! -f "${dir}/index.ts" || -L "${dir}/index.ts" ]]; then return 1; fi
  grep -qF "${_PLUGIN_SHIM_MARKER}" "${dir}/index.ts" 2>/dev/null || return 1
  grep -qE '"name"[[:space:]]*:[[:space:]]*"devbot-'"${name}"'"' "${dir}/package.json" 2>/dev/null || return 1
  rm -r -f "${dir}"
  _ok "Removed plugins/${name} — an ancestor project supplies it"
  return 0
}

# The source file an ancestor's server shim re-exports, or an empty string.
# `|| true`: a long shim can make head quit early, and pipefail would surface
# sed's SIGPIPE as a failed init.
_shim_target() {
  sed -n 's/^export { default } from "\(.*\)"$/\1/p' "$1" 2>/dev/null | head -n 1 || true
}

# Resolve a path through any symlinked directory components, so the same build
# reached through two spellings is not reported as a different one. POSIX: no
# readlink -f / realpath (absent on stock macOS).
_physical_path() {
  local path="$1" dir
  dir="$(cd "$(dirname "${path}")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "${dir}" "$(basename "${path}")"
}

# ── Link one plugin as a directory package ───────────────────────────
# V2 configured local paths must name a DIRECTORY, and a directory without a
# package.json is read through its file names — `index` is the server entry. So
# one source file becomes <dir>/index.ts.
#
# A directory source is a plugin package with several parts: `index.ts` is the
# server part, and `tui.ts` / `rpc.ts` are linked when they exist. A part is only
# linked when it exists — a `tui` export pointing at nothing makes the host
# reject the whole package.
_link_plugin_dir() {
  local name="$1"
  local src="$2"
  local dir="${V2_PLUGIN_DIR}/${name}"
  local server="${src}"
  local tui=""
  local rpc=""

  if [[ -d "${src}" ]]; then
    server="${src}/index.ts"
    if [[ -f "${src}/tui.ts" ]]; then tui="${src}/tui.ts"; fi
    if [[ -f "${src}/rpc.ts" ]]; then rpc="${src}/rpc.ts"; fi
  fi

  # One plugin id, one loaded copy. A nested project must not shadow the copy its
  # ancestor already loads: the host fails the duplicate with "Duplicate plugin
  # ID" instead of running it.
  local ancestor ancestor_target
  if ancestor="$(_ancestor_plugin_dir "${name}")"; then
    ancestor_target="$(_shim_target "${ancestor}/index.ts")"
    if [[ -n "${ancestor_target}" && ! -e "${ancestor_target}" ]]; then
      # The ancestor's package cannot import, so it holds no id and load our own.
      _warn "plugins/${name}: ${ancestor}/index.ts points at ${ancestor_target}, which is gone — writing this project's copy"
    else
      local ancestor_physical server_physical
      ancestor_physical="$(_physical_path "${ancestor_target}")" || ancestor_physical="${ancestor_target}"
      server_physical="$(_physical_path "${server}")" || server_physical="${server}"
      if [[ -n "${ancestor_target}" && "${ancestor_physical}" != "${server_physical}" ]]; then
        _warn "plugins/${name}: ${ancestor} runs a different dev-bot build — the host loads that copy first, so its version wins"
      fi
      local missing=""
      if [[ -n "${tui}" && ! -f "${ancestor}/tui.ts" ]]; then missing="tui"; fi
      if [[ -n "${rpc}" && ! -f "${ancestor}/rpc.ts" ]]; then missing="${missing:+${missing} and }rpc"; fi
      if [[ -n "${missing}" ]]; then
        _warn "plugins/${name}: the ancestor's package lacks ${missing} — a harness restart cannot add the part until that project reinitialises"
      fi
      if ! _retire_shadowed_plugin_dir "${dir}" "${name}"; then
        _warn "plugins/${name} exists and was not generated by dev-bot — duplicate registration may persist"
      fi
      _skip "plugins/${name} already loaded from ${ancestor} — not duplicated"
      return 0
    fi
  fi

  # A symlinked entry is skipped silently by the v2 loader, so each shim is a
  # real file re-exporting the single source in this module. import.meta.dir in
  # the real module still resolves to the module, so nothing is duplicated.
  _write_plugin_manifest "${dir}" "${name}" "${tui}" "${rpc}"
  _write_shim "${dir}" "index.ts" "${server}" "plugins/${name}"
  if [[ -n "${tui}" ]]; then
    _write_shim "${dir}" "tui.ts" "${tui}" "plugins/${name} tui"
  fi
  if [[ -n "${rpc}" ]]; then
    _write_shim "${dir}" "rpc.ts" "${rpc}" "plugins/${name} rpc" "all"
  fi

  # Deliberately no `plugins` config entry: v2 auto-loads every directory under
  # .opencode/plugins/, so listing one registers the same plugin twice and the
  # host fails the second copy with "Duplicate plugin ID".
}

# _write_plugin_manifest <dir> <name> [tui-source] [rpc-source]
# V2 loads a configured plugin directory as a package: without a package.json it
# tries to npm-install it and fails ("Could not read package.json").
#
# The host resolves each part through `exports`; a package that ships a TUI or
# RPC part declares it beside the server entry (the host treats a package with an
# `./rpc` export as RPC-capable). No shipped package has one today — the PTY
# extension that did is gone — but the linker keeps the capability for module
# hook packages that grow one.
_write_plugin_manifest() {
  local dir="$1" name="$2" tui_src="${3:-}" rpc_src="${4:-}"
  mkdir -p "${dir}"
  local exports='{".": "./index.ts"'
  if [[ -n "${tui_src}" ]]; then exports="${exports}"', "./tui": "./tui.ts"'; fi
  if [[ -n "${rpc_src}" ]]; then exports="${exports}"', "./rpc": "./rpc.ts"'; fi
  exports="${exports}}"
  local want
  want="$(printf '{\n  "name": "devbot-%s",\n  "version": "0.0.0",\n  "type": "module",\n  "main": "./index.ts",\n  "exports": %s\n}\n' "${name}" "${exports}")"
  local entry="${dir}/package.json"
  if [[ -f "${entry}" ]] && [[ "$(cat "${entry}")" == "${want}" ]]; then
    return 0
  fi
  printf '%s' "${want}" > "${entry}"
}

# _write_shim <dir> <file> <source> <label> [default|all]
#
# `default` re-exports a part's default export (the plugin definition); `all`
# re-exports every named export, which is what the RPC contract needs — it has
# no default export.
_write_shim() {
  local dir="$1" file="$2" src="$3" label="$4" clause="${5:-default}"
  local entry="${dir}/${file}"
  local statement="export { default } from \"${src}\""
  if [[ "${clause}" == "all" ]]; then statement="export * from \"${src}\""; fi
  local want
  want="$(printf '%s\n%s\n' "${_PLUGIN_SHIM_MARKER}" "${statement}")"

  mkdir -p "${dir}"
  if [[ -f "${entry}" && ! -L "${entry}" ]] && [[ "$(cat "${entry}")" == "${want}" ]]; then
    _skip "${label} already linked"
    return 0
  fi
  # Only a shim dev-bot generated may be replaced; a user's own entry file at
  # this name is theirs.
  if [[ (-e "${entry}" || -L "${entry}") ]] && ! grep -qF "${_PLUGIN_SHIM_MARKER}" "${entry}" 2>/dev/null; then
    _warn "${label}: ${file} exists and was not generated by dev-bot — leaving it alone"
    return 0
  fi
  rm -f "${entry}"
  printf '%s' "${want}" > "${entry}"
  _ok "${label} linked"
}

# ── Link module hooks declared under hooks/opencode/ ──────────────────────────
_link_plugins() {
  local mod_dir="$1"
  local hook_dir="${mod_dir}hooks/opencode"
  [[ ! -d "${hook_dir}" ]] && return 0

  while IFS= read -r -d '' plugin_file; do
    local plugin_name
    plugin_name="$(basename "${plugin_file}" .ts)"

    # Test files are not plugins.
    [[ "${plugin_name}" == *.test ]] && continue

    # A hook declared with a `plugin` entry in the module's hooks.json is loaded
    # by the on-hooks adapter — registering it standalone would double-register.
    if [[ -f "${mod_dir}hooks.json" ]] && python3 -c "
import json, os, sys
try:
    manifest = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
name = sys.argv[2]
for h in manifest.get('hooks', []):
    p = h.get('plugin', '')
    if p and os.path.basename(p).startswith(name):
        sys.exit(0)
sys.exit(1)
" "${mod_dir}hooks.json" "${plugin_name}" 2>/dev/null; then
      _skip "v2/plugins/${plugin_name} manifest-driven — skipping standalone registration"
      continue
    fi

    _link_plugin_dir "${plugin_name}" "${plugin_file}"
  done < <(find "${hook_dir}" -maxdepth 1 -type f -name '*.ts' -print0 2>/dev/null)
}

_link_plugins_modules() {
  local disabled_modules
  disabled_modules="$(_devbot_disabled_module_names "${PROJECT_DIR}")"

  local mod_dir mod_name
  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    mod_name="${mod_dir%/}"
    mod_name="${mod_name##*/}"
    if _devbot_list_has "${mod_name}" "${disabled_modules}"; then
      _skip "${mod_name}: disabled per config — skipping"
      continue
    fi
    _link_plugins "${mod_dir}"
  done
}

# ── Register module-declared V2 plugins ───────────────────────────────────────
# Modules declare plugins in plugin.opencode-v2.json (a JSON array of package or
# path specs). plugin.opencode.json is deliberately NOT read: those are V1
# plugins, and V1 plugin implementations do not run on V2 — registering one would
# only add a plugin that never loads.
_link_module_plugins() {
  local disabled_modules
  disabled_modules="$(_devbot_disabled_module_names "${PROJECT_DIR}")"

  local mod_dir mod_name plugin_file
  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    mod_name="${mod_dir%/}"
    mod_name="${mod_name##*/}"
    if _devbot_list_has "${mod_name}" "${disabled_modules}"; then
      continue
    fi

    if [[ -f "${mod_dir}plugin.opencode.json" && ! -f "${mod_dir}plugin.opencode-v2.json" ]]; then
      _skip "${mod_name}: declares a V1 plugin only — not registered on a v2 host"
      continue
    fi

    plugin_file="${mod_dir}plugin.opencode-v2.json"
      [[ -f "${plugin_file}" ]] || continue
    local plugin
    while IFS= read -r plugin; do
      [[ -z "${plugin}" ]] && continue
      # .opencode/plugins/ is auto-loaded: a config entry there duplicates the
      # plugin, and v2 fails the second registration.
      [[ "${plugin}" == ".opencode/plugins/"* ]] && continue
      _v2 upsert-plugin "${CONFIG}" "${plugin}" >/dev/null 2>&1 || true
    done < <(jq -r '.[]' "${plugin_file}" 2>/dev/null)
  done
}

# ── Link this module's own plugins ─────────────────────────────────────
# A bare `.ts` here is a server part; a directory is a package carrying its parts
# (`index.ts` plus any `tui.ts` / `rpc.ts`). _link_plugin_dir links both.
_link_harness_hooks() {
  local hook_dir="${MODULE_DIR}/hooks"
  [[ -d "${hook_dir}" ]] || return 0

  local hook_path hook_name
  while IFS= read -r -d '' hook_path; do
    hook_name="$(basename "${hook_path}")"
    if [[ -d "${hook_path}" ]]; then
      # Test files live beside the module they test; a directory without a
      # server entry is not a plugin package.
      if [[ -f "${hook_path}/index.ts" ]]; then
        _link_plugin_dir "${hook_name}" "${hook_path}"
      fi
      continue
    fi
    [[ "${hook_name}" == *.test.ts ]] && continue
    _link_plugin_dir "${hook_name%.ts}" "${hook_path}"
  done < <(find "${hook_dir}" -maxdepth 1 \( -type f -name '*.ts' -o -type d \) -print0 2>/dev/null)
}

# ── Reconcile dev-bot's REQUIRED plugins into an already-seeded config ───────
# Only a spec that lives outside .opencode/plugins/ needs a config entry. Every
# plugin this build ships is auto-loaded from that directory, so adding one there
# would register it twice; _reconcile_plugins below removes such entries from a
# config seeded before this rule existed.
_ensure_required_plugins() {
  local manifest="${MODULE_DIR}/required-plugins.jsonc"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  [[ -f "${manifest}" && -f "${CONFIG}" && -f "${reader}" ]] || return 0

  local spec
  while IFS= read -r spec; do
    [[ -n "${spec}" ]] || continue
    [[ "${spec}" == ".opencode/plugins/"* ]] && continue
    if _v2 get "${CONFIG}" plugins 2>/dev/null | grep -qF "\"${spec}\""; then
      continue
    fi
    _v2 upsert-plugin "${CONFIG}" "${spec}" >/dev/null 2>&1 || true
    _ok "opencode.jsonc: added '${spec}' (required by dev-bot, absent from an existing config)"
  done < <(
    python3 "${reader}" "${manifest}" server 2>/dev/null |
      jq -r '.[]? | select(type=="string")' 2>/dev/null
  )
}

# ── Modules this harness already provides natively ───────────────────────────
# OpenCode 2.x ships a first-class `websearch` tool. The devbot `websearch`
# module adds one MCP server pinned to one tool (`web_search_exa`) plus its
# schema and instruction block in every session — a duplicate search surface and
# nothing else. The exclusion is UNCONDITIONAL: not a consequence of the
# module's enabled flag, so no configuration can re-enable it on this harness.
# Harnesses without a built-in search (claudecode) keep the module.
_v2_native_redundant_modules() { printf '%s\n' websearch; }

_v2_is_native_redundant() {
  local name="$1" candidate
  while IFS= read -r candidate; do
    [[ -n "${candidate}" && "${candidate}" == "${name}" ]] && return 0
  done < <(_v2_native_redundant_modules)
  return 1
}

# The URL the module itself declares for the server it would have registered.
# Ownership is decided on it: a server under the module's name that points
# somewhere else is the user's, not dev-bot's, and must survive.
_native_module_url() {
  local name="$1" manifest
  manifest="${DEV_BOT_ROOT}/src/agentic/${name}/mcp.json"
  [[ -f "${manifest}" ]] || return 0
  python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${manifest}" mcp "${name}" url 2>/dev/null || true
}

# Say why, and retire an entry an earlier init (or a merge) already wrote —
# merge-mcp is add-only, so silence here would leave the duplicate server live in
# every session while the code claimed to exclude it.
#
# Ownership first: a project may have configured its own MCP service under the
# module's name, and silently deleting it on every reinit would be worse than the
# duplicate this exclusion removes. Only the entry matching the module's own URL
# is ours to delete; anything else is reported and left alone.
_reconcile_native_module_mcps() {
  local name canonical existing existing_url
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    _notice "${name}: opencode-v2 has a built-in ${name} tool, so this module's MCP is not registered here — it would only duplicate it. Other harnesses still get it."

    existing="$(_v2 get "${CONFIG}" "mcp.servers.${name}" 2>/dev/null || true)"
    [[ -n "${existing}" ]] || continue

    canonical="$(_native_module_url "${name}")"
    # `_v2 get` prints JSON, so unwrap the string before comparing.
    existing_url="$(_v2 get "${CONFIG}" "mcp.servers.${name}.url" 2>/dev/null | jq -r '.' 2>/dev/null || true)"
    if [[ -z "${canonical}" || "${existing_url}" != "${canonical}" ]]; then
      _notice "${name}: left your own '${name}' MCP server in place — it is not the one this module declares"
      continue
    fi

    if _v2 remove-mcp "${CONFIG}" "${name}" >/dev/null 2>&1; then
      _ok "${name}: removed the MCP entry this harness provides natively"
    else
      _warn "${name}: could not remove its MCP entry from ${CONFIG}"
    fi
  done < <(_v2_native_redundant_modules)
}

# ── Register every enabled module's canonical MCP manifest ────────────────────
# bin/init.sh registers MCPs only when the selected harness is `opencode`
# (_resolve_opencode_config returns nothing for this harness), so this module
# does its own pass. The translator produces the v1 opencode shape; the only v2
# delta is per-server enablement, which is inverted: `enabled` → `disabled`.
_register_module_mcps() {
  local translate="${DEV_BOT_ROOT}/src/_shared/mcp_translate.py"
  [[ -f "${translate}" ]] || return 0

  local disabled_names gpu
  disabled_names="$(_devbot_disabled_module_names "${PROJECT_DIR}")"
  gpu="$(_qmd_gpu_value)"

  # Collect every manifest first, then translate and write them in one pass.
  # Each _v2 or translator call is an interpreter launch, and one launch per
  # module (or per server) cost more than the rest of init together.
  local manifests=() base mod_dir mod_name manifest
  for base in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    [[ -d "${base}" ]] || continue
    for mod_dir in "${base}"/*/; do
      mod_name="${mod_dir%/}"
      mod_name="${mod_name##*/}"
      if _devbot_list_has "${mod_name}" "${disabled_names}"; then
        continue
      fi
      # A module whose capability this harness provides natively is never
      # registered, whatever its enabled flag says.
      if _v2_is_native_redundant "${mod_name}"; then
        continue
      fi

      manifest="${mod_dir%/}/mcp.json"
      [[ -f "${manifest}" ]] || continue

      # A v2 plugin provides the server, so its MCP entry is skipped. A v1-only
      # plugin does not load under 2.x, so the canonical MCP is the only path.
      [[ -f "${mod_dir%/}/plugin.opencode-v2.json" ]] && continue
      if [[ -f "${mod_dir%/}/plugin.opencode.json" ]]; then
        _notice "${mod_name}: v1 plugin does not load under 2.x — registering its MCP instead"
      fi

      manifests+=("${manifest}")
    done
  done

  [[ ${#manifests[@]} -gt 0 ]] || return 0

  local batch="" sep="" owners="" owner_mod key def_v2 owner
  local seen=$'\n'
  while IFS=$'\t' read -r owner_mod key def_v2; do
    [[ -n "${owner_mod}" && -n "${key}" && -n "${def_v2}" ]] || continue
    # Two modules can declare the same server name. merge-mcp is insert-only,
    # so the first declaration won; a JSON object would let the later one
    # overwrite it, so drop the duplicate here and keep that behaviour.
    if _devbot_list_has "${key}" "${seen}"; then
      continue
    fi
    seen+="${key}"$'\n'
    batch+="${sep}\"${key}\":${def_v2}"
    sep=","
    owners+="${key}"$'\t'"${owner_mod}"$'\n'
  done < <(python3 "${translate}" --batch --harness opencode --gpu "${gpu}" \
    --root "${DEV_BOT_ROOT}" "${manifests[@]}" 2>/dev/null |
    jq -r --arg cwd "${PROJECT_DIR}" '
      select(.servers) | .module as $m | .servers | to_entries[]
      | .key as $k
      | (.value
          | (if has("enabled") then (if .enabled then .disabled = false else .disabled = true end) | del(.enabled) else . end)
          | (if .type == "local" and (has("cwd") | not) then .cwd = $cwd else . end)
        ) as $d
      | "\($m)\t\($k)\t\($d | tojson)"' 2>/dev/null || true)

  [[ -n "${batch}" ]] || return 0

  local added
  added="$(_v2 merge-mcps "${CONFIG}" "{${batch}}" 2>/dev/null || true)"
  local owner_key owner_module
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    # Owner from the shell data, not a per-server awk: this loop runs once per
    # registered server and a launch here would undo the batching it reports.
    owner=""
    while IFS=$'\t' read -r owner_key owner_module; do
      if [[ "${owner_key}" == "${key}" ]]; then
        owner="${owner_module}"
        break
      fi
    done <<<"${owners}"
    _ok "registered MCP '${key}' from ${owner}"
  done <<<"${added}"
}

# ── Register dynamic MCP manifests written by module inits ────────────────────
_register_dynamic_mcps() {
  [[ -d "${OPENCODE_DIR}" ]] || return 0

  local disabled_names
  disabled_names="$(_devbot_disabled_module_names "${PROJECT_DIR}")"

  local manifest key def def_v2 existing
  local manifest_name
  for manifest in "${OPENCODE_DIR}/"*.mcp.json; do
    [[ -f "${manifest}" ]] || continue
    manifest_name="${manifest##*/}"

    if _devbot_manifest_owner_disabled "${manifest_name}" "${disabled_names}"; then
      _skip "${manifest_name}: owning module disabled — not registering"
      continue
    fi

    key=$(jq -r 'keys[0]' "${manifest}" 2>/dev/null || true)
    [[ -z "${key}" || "${key}" == "null" ]] && continue
    def=$(jq -c --arg k "${key}" '.[$k]' "${manifest}" 2>/dev/null || true)
    [[ -z "${def}" || "${def}" == "null" ]] && continue
    def_v2="$(jq -c --arg cwd "${PROJECT_DIR}" '(if has("enabled") then (if .enabled then .disabled = false else .disabled = true end) | del(.enabled) else . end) | (if .type == "local" and (has("cwd") | not) then .cwd = $cwd else . end)' <<<"${def}" 2>/dev/null || printf '%s' "${def}")"

    # A dynamic entry is machine-generated, not user-owned: replace it when the
    # emitted definition changed, else the change would be fresh-install-only.
    existing="$(_v2 get "${CONFIG}" "mcp.servers.${key}" 2>/dev/null || true)"
    if [[ -n "${existing}" ]]; then
      if [[ "$(jq -Sc . <<<"${existing}" 2>/dev/null)" != "$(jq -Sc . <<<"${def_v2}" 2>/dev/null)" ]]; then
        _v2 remove-mcp "${CONFIG}" "${key}" >/dev/null 2>&1 || true
      fi
    fi

    if _v2 merge-mcp "${CONFIG}" "${key}" "${def_v2}" >/dev/null 2>&1; then
      _ok "Registered dynamic MCP '${key}' from ${manifest_name}"
    fi
  done
}

# ── Link the MCP wrapper scripts modules declare ─────────────────────────────
# Modules declare (`mcp.json` `assets`); the harness creates them, so the
# selected harness gets them regardless of which one it is.
_link_mcp_assets() {
  _devbot_link_harness_assets "${PROJECT_DIR}" ".opencode"
}

# ── Pin every local MCP server to the project directory ──────────────────────
# Slotted after registration so entries carried over from a migrated v1 config
# are covered too — without it their relative wrapper paths exit 127.
_ensure_mcp_cwd() {
  [[ -f "${CONFIG}" ]] || return 0
  local changed
  changed="$(_v2 ensure-mcp-cwd "${CONFIG}" "${PROJECT_DIR}" 2>/dev/null || true)"
  if [[ -n "${changed}" && "${changed}" -gt 0 ]]; then
    _ok "pinned ${changed} local MCP server(s) to ${PROJECT_DIR}"
  fi
}

# ── Drop plugin entries whose local package no longer exists ──────────────────
# Retire plugin packages dev-bot generated that this build no longer ships, and
# the v1 harness's plugin links. Only a shim carrying the marker is ours; a
# user's own package or file at the same path is left alone.
_retire_stale_plugin_dirs() {
  local plugins_dir="${OPENCODE_DIR}/plugins"
  [[ -d "${plugins_dir}" ]] || return 0

  local declared
  declared="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" \
    "${MODULE_DIR}/required-plugins.jsonc" server 2>/dev/null |
    jq -r '.[]?' 2>/dev/null || true)"

  local dir name link target
  for dir in "${plugins_dir}"/*/; do
    [[ -d "${dir}" ]] || continue
    # A symlink here is a pointer, not a package: removing through it would
    # delete whatever it names.
    [[ -L "${dir%/}" ]] && continue
    # The marker must come from a file we wrote, not through a link a user
    # pointed at something that happens to contain it.
    [[ -L "${dir}index.ts" ]] && continue
    [[ -f "${dir}index.ts" ]] && grep -qF "${_PLUGIN_SHIM_MARKER}" "${dir}index.ts" 2>/dev/null || continue
    name="${dir%/}"
    name="${name##*/}"
    _devbot_list_has ".opencode/plugins/${name}" "${declared}" && continue
    rm -r -f "${dir}"
    _ok "Removed retired plugin package ${name}"
  done

  for link in "${plugins_dir}"/*.ts; do
    [[ -L "${link}" ]] || continue
    target="$(readlink "${link}" 2>/dev/null || true)"
    case "${target}" in
      "${DEV_BOT_ROOT}"/*)
        rm -f "${link}"
        _ok "Removed v1 plugin link $(basename "${link}")"
        ;;
    esac
  done
}

_reconcile_plugins() {
  [[ -f "${CONFIG}" ]] || return 0
  local spec target redundant=0 removed=0
  while IFS= read -r spec; do
    [[ -n "${spec}" ]] || continue
    [[ "${spec}" == ".opencode/"* ]] || continue
    target="${PROJECT_DIR}/${spec}"
    # An entry under .opencode/plugins/ is always redundant: v2 auto-loads that
    # directory, so listing it registers the plugin twice and the host fails the
    # second copy with "Duplicate plugin ID".
    if [[ "${spec}" == ".opencode/plugins/"* ]]; then
      if _v2 remove-plugin "${CONFIG}" "${spec}" >/dev/null 2>&1; then
        redundant=$((redundant + 1))
      fi
      continue
    fi
    if [[ ! -d "${target}" ]]; then
      if _v2 remove-plugin "${CONFIG}" "${spec}" >/dev/null 2>&1; then
        removed=$((removed + 1))
      fi
    fi
  done < <(_v2 get "${CONFIG}" plugins 2>/dev/null | jq -r '.[]? | select(type=="string")' 2>/dev/null || true)

  if [[ ${redundant} -gt 0 ]]; then
    _ok "Dropped ${redundant} redundant plugin entrie(s) — .opencode/plugins/ is auto-loaded"
  fi
  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} stale plugin entrie(s) pointing at missing packages"
  fi
}

# ── Retire the v1 project TUI config's plugin list ────────────────────────────
# This harness seeds no project tui.json: v2 takes terminal plugins from the
# global cli.json and carries TUI parts as plugin-package exports. opencode 2.3
# still APPLIES a project tui.json it finds, and the v1 seed re-declared
# opencode-tabs@0.3.0 — which 2.3's module validator rejects — plus three
# ./tui-plugins/* paths this harness no longer links. Strip exactly the v1 dist's
# entries; a project's own additions and the plugin_enabled block stay.
_retire_legacy_tui_config() {
  local tui="${OPENCODE_DIR}/tui.json"
  local v1_dist="${DEV_BOT_ROOT}/src/harnesses/opencode/tui.dist.jsonc"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  [[ -f "${tui}" && -f "${v1_dist}" && -f "${reader}" ]] || return 0

  local spec retired=0
  while IFS= read -r spec; do
    [[ -n "${spec}" ]] || continue
    if _v2 remove-tui-plugin "${tui}" "${spec}" >/dev/null 2>&1; then
      retired=$((retired + 1))
    fi
  done < <(
    python3 "${reader}" "${v1_dist}" plugin 2>/dev/null |
      jq -r '.[]? | select(type=="string")' 2>/dev/null
  )

  if [[ ${retired} -gt 0 ]]; then
    _ok "Retired ${retired} v1 TUI plugin entrie(s) from .opencode/tui.json"
  fi
}

# ── Reconcile external_directory: deny-first with /tmp/** allowed ─────────────
_reconcile_external_directory() {
  [[ -f "${CONFIG}" ]] || return 0
  local added rc=0
  added="$(_v2 ensure-external-directory "${CONFIG}" 2>/dev/null)" || rc=$?
  if [[ "${added}" == "1" ]]; then
    _ok "external_directory reconciled: deny-first, /tmp/** allowed"
  elif (( rc != 0 )); then
    _warn "external_directory reconcile failed (${CONFIG})"
  fi
}

# ── Default agent ─────────────────────────────────────────────────────────────
_ensure_default_agent() {
  [[ -f "${CONFIG}" ]] || return 0

  local current
  current="$(_v2 get "${CONFIG}" default_agent 2>/dev/null | tr -d '"' || true)"

  if [[ -n "${current}" && "${current}" == "devbot" ]]; then
    _skip "default agent is devbot"
    return 0
  fi

  if [[ "${SKIP_CONFIRM:-0}" == "1" || ! -t 0 ]]; then
    _skip "default agent is '${current:-unset}' — leaving as-is (non-interactive)"
    return 0
  fi

  echo -n "  Default agent is '${current:-unset}'. Set devbot as the default agent? [y/N] "
  local answer
  read -r answer
  if [[ ! "${answer}" =~ ^[yY](es)?$ ]]; then
    _info "Leaving default agent as '${current:-unset}'."
    return 0
  fi

  _v2 set-default-agent "${CONFIG}" devbot >/dev/null 2>&1 || true
  _ok "default agent set to devbot"
}

# ── Ensure a non-empty AGENTS.md (referenced in dist instructions) ────────────
_ensure_agents_md() {
  local project_dir="${1:-${PROJECT_DIR:-$(pwd)}}"
  local agents_md="${project_dir}/AGENTS.md"
  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"

  if [[ -f "${agents_md}" && -s "${agents_md}" ]]; then
    _skip "AGENTS.md already populated"
    return 0
  fi

  cat > "${agents_md}" <<EOF
# Agent Instructions

Always-on context lives in the memory vault:
${devbot_dir}/memory/active/**/*.md
EOF
  _ok "Wrote AGENTS.md pointer to ${devbot_dir}/memory/active/"
}

# ── Delegate .opencode/* artifact dirs to devbot_dir/ ─────────────────────────
_delegate_harness_dirs() {
  # `skills` is NOT delegated as a directory (see _link_skill_farm): .opencode/
  # skills also holds module-authored links, and a directory symlink would move
  # those writes into the project vault. User content already there is migrated
  # into the vault first, so nothing is lost.
  _harness_delegate_type "${OPENCODE_DIR}" "${PROJECT_DIR}" "skills" "true"
  _harness_delegate_to_agents "${OPENCODE_DIR}" "${PROJECT_DIR}" "agents commands tools"
}

# ── Wire the skill farm into .opencode/skills ────────────────────────────────
# A 2.x host scans ONLY <project>/.opencode/skill(s) — plus the global
# ~/.opencode and ~/.config/opencode equivalents. It does NOT discover
# <devbot_dir>/skills the way v1 does, and its own log says so:
#
#   message="skills rescanned" sources="[…/.opencode/skill,…/.opencode/skills]"
#
# Delegating `skills` migrate-only therefore left the whole farm on disk and
# unregistered: every devbot skill was unloadable (audit-01 FAIL-4 — the farm
# existed, nothing scanned it).
#
# One link per FARM ENTRY, not one link for the farm: `.opencode/skills` also
# holds module-authored links (sentry, signoz → storage/<module>/skills), and
# making `.opencode/skills` itself a symlink to the vault would relocate their
# writes into the project and let the handover sweep descend into the farm.
#
# The link name is the farm entry — `devbot` for the module tree, plus each
# external module — and the skill id a 2.x host derives is the SKILL.md parent
# directory below it, i.e. `devbot:<skill>` for module skills.
_link_skill_farm() {
  local project_dir="${1:-${PROJECT_DIR}}"
  local devbot_dir farm target
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"
  farm="${project_dir}/${devbot_dir}/skills"
  target="${OPENCODE_DIR}/skills"

  [[ -d "${farm}" ]] || return 0
  mkdir -p "${target}"

  local desired="" entry name link
  while IFS= read -r -d '' entry; do
    name="$(basename "${entry}")"
    [[ "${name}" == ".gitkeep" ]] && continue
    desired+="${name}"$'\n'
    link="${target}/${name}"
    if [[ -L "${link}" && "$(readlink "${link}")" == "${entry}" ]]; then
      continue
    fi
    if [[ -e "${link}" && ! -L "${link}" ]]; then
      _warn "skills/${name} exists and is not a symlink — leaving it"
      continue
    fi
    ln -sfn "${entry}" "${link}"
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

  # Prune the links this function owns (they point into the farm) once the farm
  # stops providing them. A module's own link (sentry, signoz) points elsewhere
  # and is never touched.
  local stale resolved
  while IFS= read -r -d '' stale; do
    name="$(basename "${stale}")"
    _devbot_list_has "${name}" "${desired}" && continue
    resolved="$(readlink "${stale}" 2>/dev/null || true)"
    [[ -n "${resolved}" ]] || continue
    # `readlink -f` is absent on stock macOS; resolve the target's directory by
    # hand. Kept self-contained so the test can eval this function in isolation.
    [[ "${resolved}" == /* ]] || resolved="$(dirname "${stale}")/${resolved}"
    local rd
    rd="$(cd "$(dirname "${resolved}")" 2>/dev/null && pwd -P)" || continue
    resolved="${rd}/$(basename "${resolved}")"
    # Own it only when the target IS the farm or lives under it: a prefix test
    # would also claim a sibling such as `<farm>-backup`.
    [[ "${resolved}" == "${farm}" || "${resolved}" == "${farm}"/* ]] || continue
    rm -f "${stale}"
    _ok "skills/${name} unlinked (no longer in ${devbot_dir}/skills)"
  done < <(find "${target}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)

  _ok "skills wired into .opencode/skills (one link per farm entry)"
}

# ── main ───────────────────────────────────────────────────────────────────────
_copy_opencode_dir
_write_opencode_config
_migrate_legacy_config
_sweep_foreign_artifacts
_ensure_required_plugins
_ensure_agents_md
_delegate_harness_dirs
_link_skill_farm "${PROJECT_DIR}"
_prune_stale_skill_copies "${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/skills"
_devbot_apply_runtime_mcps "${PROJECT_DIR}"
_link_mcp_assets
_link_harness_hooks
_link_plugins_modules
_link_module_plugins
_register_module_mcps
_register_dynamic_mcps
_reconcile_native_module_mcps
_ensure_mcp_cwd
_retire_stale_plugin_dirs
_retire_pty_dependency
_reconcile_plugins
_retire_legacy_tui_config
_reconcile_external_directory
_remove_gitkeep_files
_ensure_default_agent
