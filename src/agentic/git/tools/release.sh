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

# ── readiness ────────────────────────────────────────────────────────────────

# Remotes that would receive a release, space-separated.
_release_remotes() {
  local remote out=""
  for remote in $(_remotes_to_use); do
    if _remote_supports_releases "${remote}"; then out="${out} ${remote}"; fi
  done
  printf '%s\n' "${out# }"
}

# Sets RELEASE_BLOCKER when a remote would push to a repository other than the one
# the release targets; returns 0 when it does. Host and path both count, and a
# remote with several push URLs is refused: `git push` fans out to all of them,
# so one validated destination would not prove the others.
_assert_release_identity() { # <remote>
  local remote="$1" push_urls push_url push_host push_slug
  local fetch_url fetch_host fetch_slug
  push_urls="$(git config --get-all "remote.${remote}.pushurl" 2>/dev/null || true)"
  [[ -n "${push_urls}" ]] || return 1
  if [[ "$(printf '%s\n' "${push_urls}" | wc -l | tr -d ' ')" -gt 1 ]]; then
    RELEASE_BLOCKER="'${remote}' has more than one push URL — a release needs one destination"
    return 0
  fi
  fetch_url="$(git config --get-all "remote.${remote}.url" 2>/dev/null | head -n1 || true)"
  [[ -n "${fetch_url}" ]] || return 1
  push_url="${push_urls}"
  read -r push_host push_slug < <(_url_parts "${push_url}") || true
  read -r fetch_host fetch_slug < <(_url_parts "${fetch_url}") || true
  [[ -n "${push_slug}" && -n "${fetch_slug}" ]] || return 1
  if [[ "${push_host}" != "${fetch_host}" || "${push_slug}" != "${fetch_slug}" ]]; then
    RELEASE_BLOCKER="'${remote}' pushes to ${push_host}/${push_slug} but the release targets ${fetch_host}/${fetch_slug} — point both at one repository"
    return 0
  fi
  return 1
}

# Sets RELEASE_BLOCKER and returns 0 when this release cannot be published yet.
# RELEASE_TAG_ABSENT marks the one case that is not a problem: no tag anywhere
# yet, which is the normal path where this run creates it.
# Plan and release call it, so the preview cannot promise a step release refuses.
_release_blocker() { # <version> <notes-file or empty>
  RELEASE_BLOCKER=""
  RELEASE_TAG_ABSENT=0
  local version="$1" notes="$2" tag_body notes_body remote remote_sha
  if ! _tag_exists_locally "${version}"; then
    # A tag pushed by an earlier run but never fetched is not a future tag.
    for remote in $(_release_remotes); do
      if [[ -n "$(_remote_tag_sha "${remote}" "${version}")" ]]; then
        RELEASE_BLOCKER="tag ${version} is on '${remote}' but not here — run 'git fetch --tags' first"
        return 0
      fi
    done
    RELEASE_TAG_ABSENT=1
    RELEASE_BLOCKER="tag ${version} does not exist — run 'tag.sh tag' first"
    return 0
  fi
  # The notes are the tag's content and the release body, so the comparison
  # cannot be skipped when the tag is already there: without the file a preview
  # would report readiness for a tag created from other notes.
  if [[ -z "${notes}" ]]; then
    RELEASE_BLOCKER="the tag exists, so --notes-file is required to compare it"
    return 0
  fi
  # tag.sh stores the notes verbatim (--cleanup=whitespace), so the heading is
  # part of the message; comparing it keeps `# Release v1.4.0` from matching a
  # release for v1.5.0 whose remaining lines happen to be equal.
  tag_body="$(git tag -l --format='%(contents)' "${version}" 2>/dev/null \
    | sed -e 's/[[:space:]]*$//')"
  notes_body="$(sed -e 's/[[:space:]]*$//' "${notes}")"
  if [[ "${REUSE_TAG}" -ne 1 && "${tag_body}" != "${notes_body}" ]]; then
    RELEASE_BLOCKER="tag ${version} was not created from ${notes} — pass --reuse-tag to publish it anyway"
    return 0
  fi
  # Every remote is checked before any release is created: one published on the
  # first remote cannot be withdrawn when the second is missing the tag. The
  # object must be this tag, not merely a ref of that name: a force-update after
  # the push would otherwise publish against a different tag.
  local local_sha
  local_sha="$(git rev-parse "refs/tags/${version}" 2>/dev/null || true)"
  for remote in $(_release_remotes); do
    if _assert_release_identity "${remote}"; then return 0; fi
    remote_sha="$(_remote_tag_sha "${remote}" "${version}")"
    if [[ -z "${remote_sha}" ]]; then
      RELEASE_BLOCKER="tag ${version} is not on '${remote}' — run 'tag.sh push' first"
      return 0
    fi
    if [[ "${remote_sha}" != "${local_sha}" ]]; then
      RELEASE_BLOCKER="tag ${version} on '${remote}' is not the tag this run validated — re-push it"
      return 0
    fi
  done
  return 1
}

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

  if [[ -n "${release_remotes}" ]]; then
    printf '\n### Readiness\n\n'
    if _release_blocker "${version}" "${NOTES}"; then
      # Absent everywhere is the normal path: this run creates the tag. Any
      # other blocker (remote-only tag, notes mismatch, remote problem) is a
      # preview that must not promise a release.
      if [[ "${RELEASE_TAG_ABSENT}" -eq 1 ]]; then
        printf 'The tag `%s` is created and pushed by this run; the release follows it.\n' "${version}"
      else
        _fatal "plan: ${RELEASE_BLOCKER}"
      fi
    else
      printf 'Tag `%s` is present, matches the notes and is on every release-capable remote.\n' "${version}"
    fi
  fi

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

  # A release must never be published without the tag it describes: the tag is the
  # git half's product, and publishing against another run's is how a body ends up
  # describing code the tag does not contain.
  if _release_blocker "${version}" "${NOTES}"; then
    _fatal "release: ${RELEASE_BLOCKER}"
  fi

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
  release  --version V --notes-file F --remotes a,b [--reuse-tag]
                                                           publish GitHub releases
                                                           (refuses without a matching tag)

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
