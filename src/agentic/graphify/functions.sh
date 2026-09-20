#!/usr/bin/env bash
# src/agentic/graphify/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

_fmt_duration() {
  local secs=$1
  if (( secs >= 60 )); then
    printf '%dm %ds' $(( secs / 60 )) $(( secs % 60 ))
  else
    printf '%ds' "${secs}"
  fi
}

# ── Version-matched skill generation ─────────────────────────────────────────
# The graphify CLI ships the skill for the release it belongs to; dev-bot's
# committed src/agentic/graphify/skills/SKILL.md is a vendored fork that drifts
# as the CLI is upgraded — inside or outside the dev-bot lifecycle. These helpers
# regenerate the skill from the installed package (dev-bot's namespaced
# frontmatter + the package's generic skill.md body and references) into
# <DEV_BOT_ROOT>/storage/graphify/skills, stamped with the CLI version and
# marked with a `.devbot-generated` sentinel. The skills farms prefer that dir
# ONLY when the sentinel is present — so the preference is opt-in (an unrelated
# module's storage/<name>/skills is never farmed) and a failed regeneration
# falls back to the committed skill by dropping the sentinel.

# _graphify_package_dir — print the directory of the installed graphify package.
# Honours GRAPHIFY_PACKAGE_DIR (tests / exotic installs) as an authoritative
# override. Otherwise resolves the package via the stored interpreter, then uv.
# Returns non-zero when the package cannot be located.
_graphify_package_dir() {
  if [[ -n "${GRAPHIFY_PACKAGE_DIR:-}" ]]; then
    printf '%s' "${GRAPHIFY_PACKAGE_DIR}"
    return 0
  fi

  local py="${DEV_BOT_ROOT:-}/storage/secrets/graphify-python"
  local dir
  if [[ -x "${py}" ]]; then
    if dir="$("${py}" -c 'import graphify, os; print(os.path.dirname(graphify.__file__))' 2>/dev/null)" \
      && [[ -n "${dir}" && -f "${dir}/skill.md" ]]; then
      printf '%s' "${dir}"
      return 0
    fi
  fi

  if command -v uv >/dev/null 2>&1; then
    if dir="$(uv tool run --from graphifyy python3 -c 'import graphify, os; print(os.path.dirname(graphify.__file__))' 2>/dev/null | tail -n1)" \
      && [[ -n "${dir}" && -f "${dir}/skill.md" ]]; then
      printf '%s' "${dir}"
      return 0
    fi
  fi

  return 1
}

# _graphify_frontmatter <file> — print the file's leading YAML frontmatter,
# inclusive of both `---` fences.
_graphify_frontmatter() {
  awk 'BEGIN { n = 0 } /^---$/ { n++ } { print } n == 2 { exit }' "$1"
}

# _graphify_body <file> — print the file's body, dropping its frontmatter.
_graphify_body() {
  awk 'BEGIN { n = 0 } n < 2 { if (/^---$/) n++; next } { print }' "$1"
}

# _graphify_skill_is_current <target> <fallback> <version> — true when the
# generated store is sentinel-marked, matches the CLI version and still carries
# the committed frontmatter. Comparing the frontmatter too means a dev-bot-side
# frontmatter change propagates even when the CLI version is unchanged.
_graphify_skill_is_current() {
  local target="$1" fallback="$2" version="$3"
  [[ -f "${target}/SKILL.md" && -f "${target}/VERSION" && -f "${target}/.devbot-generated" ]] || return 1
  [[ "$(cat "${target}/VERSION")" == "${version}" ]] || return 1
  [[ "$(_graphify_frontmatter "${target}/SKILL.md")" == "$(_graphify_frontmatter "${fallback}")" ]]
}

# _graphify_fail_skill <target> — mark the generated store invalid: drop its
# sentinel so the skills farm falls back to the committed skill (it only prefers
# a sentinel-marked dir), and record the failure for the caller's log. The files
# stay for the next successful regeneration.
_graphify_fail_skill() {
  rm -f "$1/.devbot-generated" 2>/dev/null || true
  GRAPHIFY_SKILL_RESULT="unavailable"
}

# _graphify_ensure_skill — ensure the machine-local store holds a skill matched
# to the installed graphify version and to dev-bot's committed frontmatter.
# Returns 0 only when the store is confirmed current (already matching, or
# freshly regenerated). On every other path the store is left un-sentineled so
# the committed skill is served instead, and the function returns 1.
_graphify_ensure_skill() {
  local root="${DEV_BOT_ROOT:-}"
  [[ -n "${root}" ]] || return 1

  GRAPHIFY_SKILL_RESULT=""
  GRAPHIFY_SKILL_VERSION=""

  local target="${root}/storage/graphify/skills"
  local fallback="${root}/src/agentic/graphify/skills/SKILL.md"

  local version=""
  if command -v graphify >/dev/null 2>&1; then
    version="$(graphify --version 2>/dev/null | awk '{print $NF}')"
  fi
  if [[ -z "${version}" || ! -f "${fallback}" ]]; then
    _graphify_fail_skill "${target}"
    return 1
  fi

  if _graphify_skill_is_current "${target}" "${fallback}" "${version}"; then
    GRAPHIFY_SKILL_RESULT="current"
    GRAPHIFY_SKILL_VERSION="${version}"
    return 0
  fi

  local pkg=""
  if ! pkg="$(_graphify_package_dir)" || [[ ! -f "${pkg}/skill.md" ]]; then
    _graphify_fail_skill "${target}"
    return 1
  fi

  # Build in a sibling dir, then swap in. The previous store survives until the
  # new one is in place, so a failure never leaves the farm with a dangling link.
  local staging="${target}.tmp.$$"
  rm -rf "${staging}"
  if ! mkdir -p "${staging}"; then
    _graphify_fail_skill "${target}"
    return 1
  fi

  if ! {
    _graphify_frontmatter "${fallback}"
    _graphify_body "${pkg}/skill.md"
  } > "${staging}/SKILL.md"; then
    rm -rf "${staging}"
    _graphify_fail_skill "${target}"
    return 1
  fi

  if [[ -d "${pkg}/skills/opencode/references" ]] \
    && ! cp -R "${pkg}/skills/opencode/references" "${staging}/references"; then
    rm -rf "${staging}"
    _graphify_fail_skill "${target}"
    return 1
  fi

  printf '%s\n' "${version}" > "${staging}/VERSION"
  : > "${staging}/.devbot-generated"

  mkdir -p "$(dirname "${target}")"
  local old="${target}.old.$$"
  rm -rf "${old}"
  if [[ -e "${target}" ]] && ! mv "${target}" "${old}"; then
    rm -rf "${staging}"
    _graphify_fail_skill "${target}"
    return 1
  fi
  if ! mv "${staging}" "${target}"; then
    [[ -e "${old}" ]] && mv "${old}" "${target}"
    rm -rf "${staging}"
    _graphify_fail_skill "${target}"
    return 1
  fi
  rm -rf "${old}"
  GRAPHIFY_SKILL_RESULT="regenerated"
  GRAPHIFY_SKILL_VERSION="${version}"
  return 0
}

# _graphify_log_skill_result — log the _graphify_ensure_skill outcome uniformly
# across install.sh / update.sh / init.sh (it reads the status globals).
_graphify_log_skill_result() {
  case "${GRAPHIFY_SKILL_RESULT:-}" in
    regenerated) _ok "graphify skill regenerated${GRAPHIFY_SKILL_VERSION:+ for ${GRAPHIFY_SKILL_VERSION}}" ;;
    current) _skip "graphify skill already matches${GRAPHIFY_SKILL_VERSION:+ ${GRAPHIFY_SKILL_VERSION}}" ;;
    *) _warn "graphify skill could not be generated from the installed CLI — using dev-bot's bundled skill" ;;
  esac
}

# _graphify_relink_skill <project_dir> — point the project's skills-farm entry at
# the generated skill dir when it is sentinel-marked, else at the committed
# fallback. Mirrors _link_skills' preference and restores the fallback when
# regeneration failed. Needed because the linking pass runs BEFORE this module's
# init. Idempotent.
_graphify_relink_skill() {
  local project_dir="$1"
  local root="${DEV_BOT_ROOT:-}"
  local generated="${root}/storage/graphify/skills"
  local committed="${root}/src/agentic/graphify/skills"

  local want="${committed}"
  [[ -f "${generated}/.devbot-generated" ]] && want="${generated}"

  local devbot_dir link
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"
  link="${project_dir}/${devbot_dir}/skills/devbot/graphify"
  if [[ -L "${link}" && "$(readlink "${link}")" == "${want}" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${link}")"
  if [[ -e "${link}" && ! -L "${link}" ]]; then
    _warn "skills/devbot/graphify exists but is not a symlink — leaving it"
    return 0
  fi
  rm -f "${link}"
  ln -sf "${want}" "${link}"
  _log "skills/devbot/graphify relinked"
  return 0
}
