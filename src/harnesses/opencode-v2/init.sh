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

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

# shellcheck source=../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Paths ──────────────────────────────────────────────────────────────────────

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
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
# the ownership record: a name in it was put there by dev-bot, and the harness
# that takes the project back may retire exactly those.
_MANAGED_DEPS_FILE=".devbot-managed-deps"

_record_managed_dependency() {
  local name="$1"
  local manifest="${OPENCODE_DIR}/${_MANAGED_DEPS_FILE}"
  mkdir -p "${OPENCODE_DIR}"
  if [[ -f "${manifest}" ]] && grep -qxF "${name}" "${manifest}" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "${name}" >> "${manifest}"
}

# ── Merge .opencode/ template directory ───────────────────────────────────────
_copy_opencode_dir() {
  if [[ ! -d "${OPENCODE_TPL}" ]]; then
    _warn "Template directory not found at ${OPENCODE_TPL}"
    return 1
  fi

  local copied=0 seeded_manifest=0
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
      if [[ "${rel}" == "package.json" ]]; then seeded_manifest=1; fi
    fi
  done < <(find "${OPENCODE_TPL}" -mindepth 1 -print0 2>/dev/null)

  # A manifest this harness seeded carries dev-bot's dependency list, so the
  # handover can retire what it declares. A pre-existing one belongs to the
  # project and is never rewritten on the way out.
  if [[ ${seeded_manifest} -eq 1 ]] && grep -q '"bun-pty"' "${OPENCODE_DIR}/package.json" 2>/dev/null; then
    _record_managed_dependency "bun-pty"
  fi

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

# ── Install the scaffold's plugin dependencies ────────────────────────────────
# v1's plugins import @opencode-ai/plugin as a TYPE only, so the scaffold's
# package.json never needed installing. The v2 plugins import @opencode/plugin
# (resolved by the host at runtime) and bun-pty (a real runtime dependency), so
# .opencode/ needs node_modules or the PTY tools report themselves unavailable.
_install_plugin_deps() {
  [[ -f "${OPENCODE_DIR}/package.json" ]] || return 0
  if [[ -d "${OPENCODE_DIR}/node_modules/bun-pty" ]]; then
    _skip "plugin dependencies already installed"
    return 0
  fi
  if [[ "${DEV_BOT_SKIP_PLUGIN_DEPS:-0}" == "1" ]]; then
    _skip "plugin dependency install skipped (DEV_BOT_SKIP_PLUGIN_DEPS=1)"
    return 0
  fi
  if ! command -v bun >/dev/null 2>&1; then
    _warn "bun not found — the PTY tools stay unavailable"
    return 0
  fi
  # Only bun-pty: @opencode/plugin is resolved by the host at runtime, and
  # installing it drags in its full dependency graph for no benefit.
  _info "Installing bun-pty into .opencode/ ..."
  # `bun add`, not `bun install`: an existing .opencode/package.json may come
  # from the v1 adapter and not declare bun-pty at all — that entry is dev-bot's.
  local declared=0
  if grep -q '"bun-pty"' "${OPENCODE_DIR}/package.json" 2>/dev/null; then declared=1; fi
  if (cd "${OPENCODE_DIR}" && timeout 120 bun add bun-pty >/dev/null 2>&1); then
    if [[ ${declared} -eq 0 ]]; then _record_managed_dependency "bun-pty"; fi
    _ok "bun-pty installed — the PTY tools are available"
  else
    _warn "bun install failed or timed out — the PTY tools stay unavailable"
  fi
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
  local removed=0 link target resolved candidate farm
  for farm in plugins plugin tui-plugins agents commands tools skills; do
    [[ -d "${OPENCODE_DIR}/${farm}" ]] || continue
  while IFS= read -r -d '' link; do
    target="$(readlink "${link}" 2>/dev/null || true)"
    [[ -n "${target}" ]] || continue
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
  local dir
  for dir in "${OPENCODE_DIR}/tui-plugins" "${OPENCODE_DIR}/v2"; do
    [[ -d "${dir}" ]] && rmdir "${dir}" 2>/dev/null || true
  done

  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} symlink(s) left by a previously selected harness"
  fi
  return 0
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
# The host resolves each part through `exports`, and reports a package with a
# server part plus an `./rpc` export as RPC-capable — the PTY sidebar needs that
# flag, so its manifest carries `./tui` and `./rpc` beside the server entry.
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
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  local mod_dir mod_name
  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    mod_name="$(basename "${mod_dir}")"
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
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
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  local mod_dir mod_name plugin_file
  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    mod_name="$(basename "${mod_dir}")"
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
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
# A bare `.ts` here is a server part; a directory is a package carrying its
# parts (the PTY extension: server, TUI and RPC). _link_plugin_dir links both.
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

# ── Register every enabled module's canonical MCP manifest ────────────────────
# bin/init.sh registers MCPs only when the selected harness is `opencode`
# (_resolve_opencode_config returns nothing for this harness), so this module
# does its own pass. The translator produces the v1 opencode shape; the only v2
# delta is per-server enablement, which is inverted: `enabled` → `disabled`.
_register_module_mcps() {
  local translate="${DEV_BOT_ROOT}/src/_shared/mcp_translate.py"
  [[ -f "${translate}" ]] || return 0

  local disabled_names gpu
  disabled_names="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null | jq -r '.[]' 2>/dev/null || true)"
  gpu="$(_qmd_gpu_value)"

  local base mod_dir mod_name manifest out key def def_v2
  for base in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    [[ -d "${base}" ]] || continue
    for mod_dir in "${base}"/*/; do
      mod_name="$(basename "${mod_dir}")"
      if echo "${disabled_names}" | grep -Fxq "${mod_name}" 2>/dev/null; then
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

      out="$(python3 "${translate}" "${manifest}" opencode --gpu "${gpu}" --root "${DEV_BOT_ROOT}" 2>/dev/null || true)"
      [[ -n "${out}" ]] || continue

      while IFS= read -r key; do
        [[ -n "${key}" ]] || continue
        def="$(jq -c --arg k "${key}" '.[$k]' <<<"${out}" 2>/dev/null || true)"
        [[ -n "${def}" ]] || continue
        def_v2="$(jq -c --arg cwd "${PROJECT_DIR}" '(if has("enabled") then (if .enabled then .disabled = false else .disabled = true end) | del(.enabled) else . end) | (if .type == "local" and (has("cwd") | not) then .cwd = $cwd else . end)' <<<"${def}" 2>/dev/null || printf '%s' "${def}")"
        if _v2 merge-mcp "${CONFIG}" "${key}" "${def_v2}" >/dev/null 2>&1; then
          _ok "registered MCP '${key}' from ${mod_name}"
        fi
      done < <(jq -r 'keys[]' <<<"${out}" 2>/dev/null || true)
    done
  done
}

# ── Register dynamic MCP manifests written by module inits ────────────────────
_register_dynamic_mcps() {
  [[ -d "${OPENCODE_DIR}" ]] || return 0

  local disabled_names
  disabled_names="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null | jq -r '.[]' 2>/dev/null || true)"

  local manifest key def def_v2 existing
  for manifest in "${OPENCODE_DIR}/"*.mcp.json; do
    [[ -f "${manifest}" ]] || continue

    if _devbot_manifest_owner_disabled "$(basename "${manifest}")" "${disabled_names}"; then
      _skip "$(basename "${manifest}"): owning module disabled — not registering"
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
      _ok "Registered dynamic MCP '${key}' from $(basename "${manifest}")"
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
    name="$(basename "${dir}")"
    printf '%s\n' "${declared}" | grep -Fxq ".opencode/plugins/${name}" && continue
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
  local delegate_types="agents commands skills tools"
  if [[ "$(_devbot_get_project_dir "${PROJECT_DIR}")" == ".agents" ]]; then
    delegate_types="agents commands tools"
    _harness_delegate_type "${OPENCODE_DIR}" "${PROJECT_DIR}" "skills" "true"
  fi
  _harness_delegate_to_agents "${OPENCODE_DIR}" "${PROJECT_DIR}" "${delegate_types}"
}

# ── main ───────────────────────────────────────────────────────────────────────
_copy_opencode_dir
_write_opencode_config
_migrate_legacy_config
_sweep_foreign_artifacts
_install_plugin_deps
_ensure_required_plugins
_ensure_agents_md
_delegate_harness_dirs
_prune_stale_skill_copies "${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/skills"
_devbot_apply_runtime_mcps "${PROJECT_DIR}"
_link_mcp_assets
_link_harness_hooks
_link_plugins_modules
_link_module_plugins
_register_module_mcps
_register_dynamic_mcps
_ensure_mcp_cwd
_retire_stale_plugin_dirs
_reconcile_plugins
_retire_legacy_tui_config
_reconcile_external_directory
_remove_gitkeep_files
_ensure_default_agent
