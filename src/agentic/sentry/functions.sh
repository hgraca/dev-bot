#!/usr/bin/env bash
# src/agentic/sentry/functions.sh
# Shared helpers for Sentry module scripts (install.sh, update.sh, init.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# The upstream source the skills CLI fetches from. getsentry/agent-plugin is the
# official Agent Plugins distribution that getsentry/sentry-for-ai builds and
# publishes; the older sentry-agent-skills repo is superseded.
_SENTRY_SKILLS_SOURCE="getsentry/agent-plugin"

# Resolve the storage directory for Sentry agent skills.
_sentry_storage_dir() {
  echo "${DEV_BOT_ROOT}/storage/sentry"
}

# Install (or refresh) the Sentry agent skills into storage/sentry/skills.
#
# Shared by install.sh (only when the skills are missing) and update.sh
# (always, to pick up upstream changes) so the two scripts cannot drift.
#
# Returns non-zero when npx is unavailable or the fetch fails; callers decide
# whether that is fatal (install) or tolerated (update).
_sentry_install_skills() {
  local skills_dir
  skills_dir="$(_sentry_storage_dir)/skills"

  if ! command -v npx >/dev/null 2>&1; then
    _warn "npx not found (node/npm required) — cannot install Sentry agent skills"
    return 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")" || {
    _warn "Could not create a temp dir — Sentry skills not installed"
    return 1
  }

  # A minimal package.json gives npx a project context and suppresses prompts.
  printf '{"name":"sentry-skills-tmp","private":true}\n' > "${tmpdir}/package.json"

  if ! (cd "${tmpdir}" && npx --yes skills add --yes "${_SENTRY_SKILLS_SOURCE}" 2>&1) | sed 's/^/  /'; then
    _warn "npx skills add failed — Sentry skills not installed."
    _warn "  Try manually: npx skills add ${_SENTRY_SKILLS_SOURCE}"
    rm -rf "${tmpdir}"
    return 1
  fi

  # The CLI writes .agents/skills; the other candidates cover version drift.
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

  _ok "Sentry agent skills installed to ${skills_dir}"
}
