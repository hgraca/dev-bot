#!/usr/bin/env bash
# =============================================================================
# src/tools/opencode/init.sh
# Sets up opencode in a project: copies the .opencode/ template directory,
# writes opencode.jsonc from the dist template, creates symlinks for agents,
# commands, skills, tools, and plugins, and removes .gitkeep files.
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
OPENCODE_TPL="${MODULE_DIR}/_opencode.tpl"
DIST_CONFIG="${MODULE_DIR}/opencode.dist.jsonc"
OPENCODE_DIR="${PROJECT_DIR}/.opencode"

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

    [[ "$(basename "${rel}")" == ".gitkeep" ]] && return

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

# ── Link plugins ───────────────────────────────────────────────────────────────
_link_plugins() {
  local mod_dir="$1"
  local hook_dir="${mod_dir}hooks/opencode"
  [[ ! -d "${hook_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  while IFS= read -r -d '' plugin_file; do
    local plugin_name
    plugin_name="$(basename "${plugin_file}")"
    local target="${plugin_file}"
    local link="${OPENCODE_DIR}/plugins/${plugin_name}"

    # Test files (bun *.test.ts) are not plugins — symlinking + registering
    # them adds noise and a pointless no-op plugin to the config.
    [[ "${plugin_name}" == *.test.ts ]] && continue

    # Hooks declared with a `plugin` entry in the module's hooks.json manifest
    # are loaded by the on-hooks adapter — symlinking and registering them
    # standalone would double-register them (adapter + direct plugin).
    if [[ -f "${mod_dir}hooks.json" ]] && python3 -c "
import json, os, sys
try:
    manifest = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
name = sys.argv[2]
for h in manifest.get('hooks', []):
    p = h.get('plugin', '')
    if p and os.path.basename(p) == name:
        sys.exit(0)
sys.exit(1)
" "${mod_dir}hooks.json" "${plugin_name}" 2>/dev/null; then
      _skip "plugins/${plugin_name} manifest-driven — skipping standalone registration"
      continue
    fi

    if [[ -L "${link}" ]]; then
      local current
      current="$(readlink "${link}")"
      if [[ "${current}" == "${target}" ]]; then
        _skip "plugins/${plugin_name} already linked"
        _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
      else
        rm -f "${link}"
        ln -sf "${target}" "${link}"
        _ok "plugins/${plugin_name} relinked"
        _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "plugins/${plugin_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${target}" "${link}"
      _ok "plugins/${plugin_name} linked"
      _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
    fi
  done < <(find "${hook_dir}" -maxdepth 1 -type f -print0 2>/dev/null)
}

# ── Write opencode.jsonc from template ─────────────────────────────────────────
_write_opencode_config() {
  local config="${PROJECT_DIR}/opencode.jsonc"

  if [[ -f "${config}" ]]; then
    _skip "opencode.jsonc already exists"
    return 0
  fi

  if [[ ! -f "${DIST_CONFIG}" ]]; then
    _warn "Template not found at ${DIST_CONFIG}"
    return 1
  fi

  _info "Writing opencode.jsonc..."

  # Copy the dist, substituting __GPU_ENABLED__ and stripping comments. The
  # dist is a template full of commented-out model/provider options; the project
  # config should be clean. Stripping is string-aware so URLs (https://…) survive.
  # __GPU_ENABLED__ becomes a qmd-valid value (metal|cuda|vulkan|false) — qmd
  # 2.8.3 rejects the plain boolean "true".
  GPU_ENABLED="$(_qmd_gpu_value)" DIST_CONFIG="${DIST_CONFIG}" CONFIG="${config}" python3 - <<'PY'
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

stripped = "".join(out).replace("__GPU_ENABLED__", os.environ["GPU_ENABLED"])
# Drop lines left blank by full-line comments; trim trailing whitespace.
lines = [line.rstrip() for line in stripped.splitlines() if line.strip()]
data = "\n".join(lines) + "\n"
# Atomic write (temp + rename) so concurrent reinits can never interleave a
# partially-written config — last writer wins whole-file.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.environ["CONFIG"]), prefix=".opencode.jsonc.")
with os.fdopen(fd, "w") as f:
    f.write(data)
os.replace(tmp, os.environ["CONFIG"])
PY
  _ok "opencode.jsonc written"
}

_link_plugins_modules() {
  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip ENTIRE module if disabled — no symlinks created
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      _skip "${mod_name}: disabled per config — skipping"
      continue
    fi

    _link_plugins "${mod_dir}"
  done
}

# ── Register module-declared plugins (plugin.opencode.json) ─────────────────
# Reads each module's plugin.opencode.json (a JSON array of plugin names) and
# registers them in the opencode.jsonc "plugin" array. Modules declare; the
# harness applies — keeping module init.sh harness-agnostic.
_link_module_plugins() {
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      continue
    fi

    local plugin_file="${mod_dir}/plugin.opencode.json"
    [[ -f "${plugin_file}" ]] || continue

    while IFS= read -r plugin; do
      [[ -z "${plugin}" ]] && continue
      _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" "${plugin}"
    done < <(jq -r '.[]' "${plugin_file}" 2>/dev/null)
  done
}

# ── Register dynamic MCP manifests written by module inits (e.g. jetbrains) ──
# Module inits emit .opencode/<name>.mcp.json (a {key: def} object) instead of
# editing opencode.jsonc directly — this harness step applies them.
_register_dynamic_mcps() {
  local merge_script="${DEV_BOT_ROOT}/src/_shared/merge_mcp_jsonc.py"
  [[ -f "${merge_script}" ]] || return 0

  local manifest key def
  for manifest in "${PROJECT_DIR}/.opencode/"*.mcp.json; do
    [[ -f "${manifest}" ]] || continue

    key=$(jq -r 'keys[0]' "${manifest}" 2>/dev/null || true)
    [[ -z "${key}" || "${key}" == "null" ]] && continue
    def=$(jq -c --arg k "${key}" '.[$k]' "${manifest}" 2>/dev/null || true)
    [[ -z "${def}" || "${def}" == "null" ]] && continue

    if python3 "${merge_script}" "${PROJECT_DIR}/opencode.jsonc" "${key}" "${def}" >/dev/null 2>&1; then
      _ok "Registered dynamic MCP '${key}' from $(basename "${manifest}")"
    fi
  done
}

# ── Link the harness module's own hooks (generic adapter + any hand-written) ──
_link_harness_hooks() {
  local hook_dir="${MODULE_DIR}/hooks"
  [[ -d "${hook_dir}" ]] || return

  while IFS= read -r -d '' hook_file; do
    local hook_name
    hook_name="$(basename "${hook_file}")"
    [[ "${hook_name}" == *.ts ]] || continue

    # Test files (bun *.test.ts) are not plugins — never link or register them.
    [[ "${hook_name}" == *.test.ts ]] && continue

    local link="${OPENCODE_DIR}/plugins/${hook_name}"
    if [[ -L "${link}" ]]; then
      _skip "plugins/${hook_name} already linked"
    elif [[ -e "${link}" ]]; then
      _warn "plugins/${hook_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${hook_file}" "${link}"
      _ok "plugins/${hook_name} linked"
    fi
    _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${hook_name}"
  done < <(find "${hook_dir}" -maxdepth 1 -type f -name '*.ts' -print0 2>/dev/null)
}

# ── Reconcile watcher.ignore with the actual plugin set ──────────────────────
# Removes stale .opencode/plugins/* entries (plugins since consolidated behind
# the on-hooks dispatcher) so the ignore list no longer references missing files.
_reconcile_watcher_ignore() {
  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local removed
  removed=$(CONFIG_PATH="${config}" PROJECT_ROOT="${PROJECT_DIR}" python3 - <<'PY' 2>/dev/null
import os, re
config = os.environ["CONFIG_PATH"]
project = os.environ["PROJECT_ROOT"]
with open(config) as f:
    lines = f.readlines()
removed = 0
out = []
for line in lines:
    m = re.match(r'^(\s*)"(\.opencode/plugins/[^"]+)"\s*,?\s*$', line)
    if m and not os.path.exists(os.path.join(project, m.group(2))):
        removed += 1
        continue
    out.append(line)
if removed:
    with open(config, "w") as f:
        f.writelines(out)
print(removed)
PY
  )

  if [[ -n "${removed}" && "${removed}" -gt 0 ]]; then
    _ok "Removed ${removed} stale watcher.ignore plugin entrie(s)"
  fi
}

# ── Reconcile external_directory: enforce deny-first with /tmp/** allowed ────
# The pre-approved scratch dir /tmp/opencode is denied by "*": "deny" unless an
# explicit recursive /tmp/** allow entry exists (a single-level "/tmp/*" glob
# does NOT match nested paths like /tmp/opencode/file.txt). Rule evaluation is
# last-match-wins: a specific allow placed BEFORE the catch-all "*" deny is
# shadowed (audit-22 FAIL — /tmp/** was unreachable despite being allow-listed).
# So the catch-all must come FIRST and every specific allow after it. Older
# configs have the single-level form or the allow-before-deny order — migrate
# both; add fresh if absent.
_reconcile_external_directory() {
  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local added
  added=$(CONFIG_PATH="${config}" python3 - <<'PY' 2>/dev/null
import json, os, re
config = os.environ["CONFIG_PATH"]
with open(config) as f:
    text = f.read()

block_m = re.search(r'"external_directory"\s*:\s*\{([^}]*)\}', text, re.S)
tmp_present = '"/tmp/**"' in text

if '"/tmp/*"' in text and not tmp_present:
    with open(config, "w") as f:
        f.write(text.replace('"/tmp/*"', '"/tmp/**"', 1))
    print("1")
    raise SystemExit

if not block_m:
    print("0")
    raise SystemExit

# Rebuild the block with "*": "deny" first, then the specific allows, so the
# allows are evaluated last and win. Covers both "stale order" (allow before
# deny) and "absent /tmp/**" (insert after the deny).
try:
    entries = json.loads("{" + block_m.group(1) + "}")
except Exception:
    print("0")
    raise SystemExit

if tmp_present and list(entries.keys())[:1] == ["*"]:
    print("0")  # already deny-first with /tmp/** — nothing to do
    raise SystemExit

ordered = {}
if "*" in entries:
    ordered["*"] = entries["*"]
for k, v in entries.items():
    if k != "*":
        ordered[k] = v
if not tmp_present:
    ordered["/tmp/**"] = "allow"

new_block = ",\n".join(f'    "{k}": "{v}"' for k, v in ordered.items())
text = text[: block_m.start(1)] + new_block + text[block_m.end(1) :]
with open(config, "w") as f:
    f.write(text)
print("1")
PY
  )

  if [[ "${added}" == "1" ]]; then
    _ok "external_directory reconciled: deny-first with /tmp/** allowed"
  fi
}

# ── Default agent ─────────────────────────────────────────────────────────────
# The agent is no longer forced at launch (start.sh). If the project's
# opencode.jsonc does not have DevBot as `default_agent`, ask the user whether
# to set it — never change an existing choice silently. Non-interactive runs
# (SKIP_CONFIRM=1 or no TTY) leave the config untouched.
_ensure_default_agent() {
  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local current
  current="$(python3 "${reader}" "${config}" default_agent 2>/dev/null || true)"

  if [[ -n "${current}" && "${current}" == "DevBot" ]]; then
    _skip "default agent is DevBot"
    return 0
  fi

  if [[ "${SKIP_CONFIRM:-0}" == "1" || ! -t 0 ]]; then
    _skip "default agent is '${current:-unset}' — leaving as-is (non-interactive)"
    return 0
  fi

  echo -n "  Default agent is '${current:-unset}'. Set DevBot as the default agent? [y/N] "
  local answer
  read -r answer
  if [[ ! "${answer}" =~ ^[yY](es)?$ ]]; then
    _info "Leaving default agent as '${current:-unset}'."
    return 0
  fi

  CONFIG_PATH="${config}" python3 - <<'PY'
import os, re
config = os.environ["CONFIG_PATH"]
with open(config) as f:
    text = f.read()
if re.search(r'"default_agent"\s*:', text):
    text = re.sub(r'("default_agent"\s*:\s*)"[^"]*"', r'\1"DevBot"', text, count=1)
else:
    text = text.replace("{", '{\n    "default_agent": "DevBot",', 1)
with open(config, "w") as f:
    f.write(text)
PY
  _ok "default agent set to DevBot"
}

# ── Ensure a non-empty AGENTS.md (referenced in dist instructions) ────────────
# The dist's opencode.jsonc template lists "AGENTS.md" in `instructions`, so
# opencode expects the file. A missing or 0-byte AGENTS.md is a stale-looking
# artifact (audit-28 NOTE-2): write a pointer to the always-on memory vault
# when the file is absent or empty. A user-populated AGENTS.md is never
# touched.
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
# opencode auto-discovers skills from .agents/skills directly, so delegating
# .opencode/skills → .agents/skills causes duplicate skill-name warnings. With
# the default .agents devbot dir, migrate user custom skills into
# .agents/skills WITHOUT the delegation symlink (they are still discovered via
# .agents/skills); with a custom devbot_dir, full delegation applies.
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
_ensure_agents_md
_delegate_harness_dirs
_link_plugins_modules
_link_module_plugins
_link_harness_hooks
_register_dynamic_mcps
_reconcile_watcher_ignore
_reconcile_external_directory
_remove_gitkeep_files
_ensure_default_agent
