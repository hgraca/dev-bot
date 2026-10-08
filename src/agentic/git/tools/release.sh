#!/usr/bin/env bash
# =============================================================================
# src/agentic/git/tools/release.sh
#
# Deterministic half of the `devbot:gh-release` skill. Every subcommand is
# non-interactive; the approval gate lives in the skill, not here.
#
#   plan     — print the GitHub release preview (read-only, mutates nothing)
#   release  — publish a GitHub release for a pushed tag
#
# The git half (merge, tag, push) lives in tag.sh; both source the shared
# plumbing in git.sh. `gh` is optional — a missing or unauthenticated CLI
# degrades to a warning, never a failure.
#
# GATE: Linux and macOS. bash 3.2-safe (no ${v,,}, no associative arrays), no
# GNU-only tools (no readlink -f, no sed -i, no sort -V).
# =============================================================================

set -euo pipefail

_GIT_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./git.sh
source "${_GIT_SH_DIR}/git.sh"

# ── plan ─────────────────────────────────────────────────────────────────────

cmd_plan() {
  _parse_common plan "$@"

  local version
  version="$(_resolve_version plan)"

  local remotes remote slug release_remotes=""
  remotes="$(_remotes_to_use)"

  printf '## GitHub release plan\n\n'
  printf -- '- **Version:** `%s`\n' "${version}"
  printf -- '- **Release title:** `%s`\n' "${version}"

  printf '\n### Remotes\n\n'
  for remote in ${remotes}; do
    if _remote_supports_releases "${remote}"; then
      slug="$(_remote_slug "${remote}")"
      printf -- '- `%s` — `%s`, release yes\n' "${remote}" "${slug}"
      release_remotes="${release_remotes} ${remote}"
    else
      slug="$(_remote_slug "${remote}")"
      if [[ -n "${slug}" ]]; then
        _warn "'${remote}' (${slug}) does not support releases"
      else
        _warn "'${remote}' has no repository slug — no release will be created"
      fi
      printf -- '- `%s` — no release\n' "${remote}"
    fi
  done

  printf '\n### What happens on approval\n\n'
  if [[ -n "${release_remotes}" ]]; then
    printf 'Create the GitHub release `%s` on:%s.\n' "${version}" \
      "$(for r in ${release_remotes}; do printf ' `%s`' "${r}"; done)"
  else
    printf 'No remote supports releases — nothing will be published.\n'
  fi
  printf '\n_No VCS change has been made yet._\n'
}

# ── release ──────────────────────────────────────────────────────────────────

cmd_release() {
  _parse_common release "$@"

  local version
  version="$(_resolve_version release)"
  [[ -n "${NOTES}" ]] || _fatal "release: --notes-file is required"
  [[ -f "${NOTES}" ]] || _fatal "release: notes file not found: ${NOTES}"
  [[ -n "${REMOTES}" ]] || _fatal "release: --remotes is required"

  if ! command -v "${RELEASE_GH}" >/dev/null 2>&1; then
    _warn "'${RELEASE_GH}' is not available — the tags were pushed but no release was created"
    return 0
  fi

  # An unauthenticated CLI is a common state (expired token, missing scope,
  # wrong account) and must degrade like an absent one, not fail the release.
  if ! "${RELEASE_GH}" auth status --hostname github.com >/dev/null 2>&1; then
    _warn "'${RELEASE_GH}' is not authenticated for github.com — the tags were pushed but no release was created"
    return 0
  fi

  local created=0 failed="" remote slug
  for remote in ${REMOTES//,/ }; do
    if ! _remote_supports_releases "${remote}"; then
      slug="$(_remote_slug "${remote}")"
      _warn "skipping '${remote}' (${slug:-no repository slug}) — it does not support releases"
      continue
    fi

    slug="$(_remote_slug "${remote}")"
    if "${RELEASE_GH}" release create "${version}" --repo "${slug}" \
      --title "${version}" --notes-file "${NOTES}" >/dev/null; then
      printf 'created release %s on %s\n' "${version}" "${remote}"
      created=$((created + 1))
    else
      failed="${failed} ${remote}"
      _error "could not create the release on '${remote}' — the tag is already pushed"
    fi
  done

  if [[ -n "${failed}" ]]; then
    _error "release creation failed for:${failed}"
    _error "remediation: gh release create ${version} --repo <slug> --title ${version} --notes-file ${NOTES}"
    exit 1
  fi
  if [[ "${created}" -eq 0 ]]; then
    _warn "no release was created"
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────

_usage() {
  cat <<'EOF'
Usage: release.sh <subcommand> [options]

Subcommands:
  plan     --version V [--remotes a,b]                     print the release preview
  release  --version V --notes-file F --remotes a,b        publish GitHub releases

Environment:
  RELEASE_GH   path to the GitHub CLI (default: gh)

The git half — merge, tag, push — is tools/tag.sh.
EOF
}

main() {
  local sub="${1:-}"
  shift || true
  case "${sub}" in
    plan) cmd_plan "$@" ;;
    release) cmd_release "$@" ;;
    "" | -h | --help) _usage ;;
    *) _fatal "unknown subcommand '${sub}'" ;;
  esac
}

main "$@"
