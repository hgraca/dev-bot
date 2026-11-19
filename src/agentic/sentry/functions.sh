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
# Shared by install.sh (only when the skills are missing), update.sh (always, to
# pick up upstream changes) and init.sh (self-healing wiring) so the three
# scripts cannot drift.
#
# --if-missing: re-check under the lock and skip when another dev-bot process
# already installed them; without it the skills are always re-fetched.
#
# Returns non-zero when npx is unavailable or the fetch fails; callers decide
# whether that is fatal (install) or tolerated (update, init).
_sentry_install_skills() {
  local only_if_missing=0
  [[ "${1:-}" == "--if-missing" ]] && only_if_missing=1

  local storage_dir skills_dir
  storage_dir="$(_sentry_storage_dir)"
  skills_dir="${storage_dir}/skills"

  if ! command -v npx >/dev/null 2>&1; then
    _warn "npx not found (node/npm required) — cannot install Sentry agent skills"
    return 1
  fi

  # Parallel inits all find it absent; one fetch
  # is enough. The subshell releases fd 200.
  (
    _devbot_lock_wait "${storage_dir}/.skills.lock" 300 \
      "gave up waiting for the Sentry skills lock" || {
      # No lock, no fetch — two writers can nest the
      # trees. Leave the dir untouched and fail.
      _warn "Could not lock ${storage_dir}/.skills.lock — Sentry skills not installed"
      exit 1
    }

    # A swap killed mid-rename leaves no live
    # tree: restore the parked copy first.
    for leftover in "${storage_dir}"/.skills.previous.*; do
      [[ -d "${leftover}" ]] || continue
      if [[ -d "${skills_dir}" ]]; then
        rm -rf "${leftover}"
      else
        mv "${leftover}" "${skills_dir}"
      fi
    done

    if (( only_if_missing )) && [[ -d "${skills_dir}" ]] \
      && [[ -n "$(ls -A "${skills_dir}" 2>/dev/null)" ]]; then
      _skip "Sentry agent skills already installed (${skills_dir}/)"
      exit 0
    fi

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")" || {
      _warn "Could not create a temp dir — Sentry skills not installed"
      exit 1
    }

    # A minimal package.json gives npx a project context and suppresses prompts.
    printf '{"name":"sentry-skills-tmp","private":true}\n' > "${tmpdir}/package.json"

    if ! (cd "${tmpdir}" && exec 200>&- \
      && npx --yes skills add --yes "${_SENTRY_SKILLS_SOURCE}" 2>&1) | sed 's/^/  /'; then
      _warn "npx skills add failed — Sentry skills not installed."
      _warn "  Try manually: npx skills add ${_SENTRY_SKILLS_SOURCE}"
      rm -rf "${tmpdir}"
      exit 1
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
      exit 1
    fi

    # Staged, then renamed: a killed copy leaves
    # staging garbage, never a partial install.
    rm -rf "${storage_dir}"/.skills.staging.*
    local staging="${storage_dir}/.skills.staging.$$"
    mkdir -p "${staging}"
    if ! cp -r "${installed}/"* "${staging}"/ 2>/dev/null \
      || [[ -z "$(ls -A "${staging}" 2>/dev/null)" ]]; then
      _warn "Copying the fetched skills failed — Sentry skills not installed"
      rm -rf "${staging}" "${tmpdir}"
      exit 1
    fi
    # Keep the old tree until the new one lands:
    # a failed rename must not leave it bare.
    local previous="${storage_dir}/.skills.previous.$$"
    rm -rf "${previous}"
    if [[ -d "${skills_dir}" ]] && ! mv "${skills_dir}" "${previous}"; then
      _warn "Could not move the old skills aside — Sentry skills left untouched"
      rm -rf "${staging}" "${tmpdir}"
      exit 1
    fi
    if ! mv "${staging}" "${skills_dir}"; then
      if [[ -d "${previous}" ]]; then mv "${previous}" "${skills_dir}" || true; fi
      _warn "Could not swap the fetched skills into ${skills_dir}"
      rm -rf "${staging}" "${tmpdir}"
      exit 1
    fi
    rm -rf "${previous}"
    rm -rf "${tmpdir}"

    _ok "Sentry agent skills installed to ${skills_dir}"
  )
}
