#!/usr/bin/env bash
# src/agentic/signoz/functions.sh
# Shared helpers for SigNoz module scripts (install.sh, update.sh, init.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Resolve the storage directory for SigNoz assets (skills, README).
_signoz_storage_dir() {
  echo "${DEV_BOT_ROOT}/storage/signoz"
}

# Install (or refresh) the SigNoz agent skills into storage/signoz/skills.
#
# Shared by install.sh (only when the skills are missing) and update.sh
# (always, to pick up upstream changes) so the two scripts cannot drift.
# The retired per-machine MCP binary used to be duplicated across both, and
# sweeping the removal through only one of them broke `devbot update`.
#
# Returns non-zero when npx is unavailable or the fetch fails; callers decide
# whether that is fatal (install) or tolerated (update).
_signoz_install_skills() {
  local skills_dir
  skills_dir="$(_signoz_storage_dir)/skills"

  if ! command -v npx >/dev/null 2>&1; then
    _warn "npx not found (node/npm required) — cannot install SigNoz agent skills"
    return 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")" || {
    _warn "Could not create a temp dir — SigNoz skills not installed"
    return 1
  }

  # A minimal package.json gives npx a project context and suppresses prompts.
  printf '{"name":"signoz-skills-tmp","private":true}\n' > "${tmpdir}/package.json"

  if ! (cd "${tmpdir}" && npx --yes skills add --yes SigNoz/agent-skills 2>&1) | sed 's/^/  /'; then
    _warn "npx skills add failed — SigNoz skills not installed."
    _warn "  Try manually: npx skills add SigNoz/agent-skills"
    rm -rf "${tmpdir}"
    return 1
  fi

  # The CLI's output layout varies by version; take the first that exists.
  local installed=""
  local candidate
  for candidate in \
    "${tmpdir}/.agents/skills" \
    "${tmpdir}/.agents" \
    "${tmpdir}/.skills" \
    "${tmpdir}/skills" \
    "${tmpdir}/node_modules"; do
    if [[ -d "${candidate}" ]]; then
      installed="${candidate}"
      break
    fi
  done

  if [[ -z "${installed}" ]]; then
    _warn "Could not locate installed skills in temp dir. Contents:"
    ls -la "${tmpdir}" 2>/dev/null | sed 's/^/    /' || true
    rm -rf "${tmpdir}"
    return 1
  fi

  rm -rf "${skills_dir}"
  mkdir -p "${skills_dir}"
  cp -r "${installed}/"* "${skills_dir}"/ 2>/dev/null || true
  rm -rf "${tmpdir}"

  _ok "SigNoz agent skills installed to ${skills_dir}"
}
