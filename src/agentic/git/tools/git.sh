#!/usr/bin/env bash
# =============================================================================
# src/agentic/git/tools/git.sh
#
# Shared plumbing for the git module's release tooling. Sourced by `tag.sh`
# (the git half) and `release.sh` (the GitHub half); it defines helpers only
# and has no side effects — the sourcing tool owns `set -euo pipefail`.
#
# GATE: Linux and macOS. bash 3.2-safe (no ${v,,}, no associative arrays), no
# GNU-only tools (no readlink -f, no sed -i, no sort -V); git's own --sort is
# used for version ordering. Needs git >= 2.23 (`git switch`), and >= 2.18 for
# `git ls-remote --sort`.
# =============================================================================

# shellcheck disable=SC2034  # library: its shared vars are consumed by the sourcing tools
DEFAULT_REMOTE="origin"
RELEASE_GH="${RELEASE_GH:-gh}"

_fatal() { echo "FATAL: $*" >&2; exit 1; }
_error() { echo "ERROR: $*" >&2; }
_warn() { echo "WARN: $*" >&2; }

# ── git plumbing helpers ─────────────────────────────────────────────────────

# Newest *version-shaped* tag on a remote, version-sorted by git itself. The
# shape rule lives in `_normalise_version` alone and is applied per candidate,
# so a major-zero repo's four-part tags and a stable repo's three-part tags are
# both recognised without a second copy of the rule here. Non-version tags
# (`nightly`, a date) are ignored: bumping one would silently produce a release
# named `nightly.1.0`. Annotated tags emit a peeled `^{}` ref alongside the real
# one — that must be filtered, or the ref reads back as `1.5.0^{}`.
_last_remote_tag() {
  local remote="$1" tag candidates
  candidates="$(git ls-remote --tags --sort=-v:refname "${remote}" 2>/dev/null \
    | sed -n 's#.*refs/tags/##p' \
    | grep -v '\^{}$' \
    | grep -E '^[0-9]+(\.[0-9]+)+$' || true)"
  [[ -n "${candidates}" ]] || return 0
  while IFS= read -r tag; do
    if _normalise_version "${tag}" >/dev/null 2>&1; then
      printf '%s\n' "${tag}"
      return 0
    fi
  done <<<"${candidates}"
}

_tag_exists_on_remote() {
  local remote="$1" version="$2" out
  out="$(git ls-remote --tags "${remote}" "refs/tags/${version}" 2>/dev/null || true)"
  [[ -n "${out}" ]]
}

_tag_exists_locally() {
  git rev-parse --verify --quiet "refs/tags/$1" >/dev/null 2>&1
}

# Version shapes. A stable release has three components (X.Y.Z; X.Y normalises
# to X.Y.0). An unstable one is marked by a leading zero and has four
# (0.X.Y.Z), whose last three components behave as major.minor.patch — the
# leading zero only records that the release is still unstable. Only digits and
# dots are allowed; anything else, or any other component count, is not a
# version.
_normalise_version() {
  local value="$1" major minor third fourth extra
  case "${value}" in
    '' | *[!0-9.]* | .* | *. | *..*) return 1 ;;
  esac
  # `read` folds everything past the named fields into the last one, so a fifth
  # component (or a malformed one) leaves `extra` set.
  IFS=. read -r major minor third fourth extra <<<"${value}"
  [[ -z "${extra}" ]] || return 1
  if [[ -z "${fourth}" ]]; then
    [[ -n "${minor}" && "${major}" != "0" ]] || return 1
    if [[ -z "${third}" ]]; then
      printf '%s.%s.0\n' "${major}" "${minor}"
    else
      printf '%s.%s.%s\n' "${major}" "${minor}" "${third}"
    fi
    return 0
  fi
  [[ "${major}" == "0" && -n "${minor}" && -n "${third}" ]] || return 1
  printf '%s\n' "${value}"
}

# Next minor: X.Y.Z → X.(Y+1).0, and for the unstable shape 0.X.Y.Z →
# 0.X.(Y+1).0.
_bump_minor() {
  local normalised major minor third fourth
  normalised="$(_normalise_version "$1")" || return 1
  IFS=. read -r major minor third fourth <<<"${normalised}"
  if [[ "${major}" == "0" ]]; then
    printf '0.%s.%s.0\n' "${minor}" "$((third + 1))"
  else
    printf '%s.%s.0\n' "${major}" "$((minor + 1))"
  fi
}

# Read-only: resolves the default branch without writing
# refs/remotes/origin/HEAD. Mutating subcommands refresh the remote-tracking
# HEAD themselves before calling this — `plan` is advertised as side-effect free
# and must stay that way.
_default_branch() {
  local ref
  ref="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "${ref}" ]]; then
    printf '%s\n' "${ref#origin/}"
  else
    printf 'main\n'
  fi
}

# The ref the release compares the source branch against: the remote-tracking
# default branch once it exists (what `merge` will integrate), else the local
# one. Read-only — safe for `plan`.
_default_base_ref() {
  if git rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null; then
    printf 'origin/%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# Subjects of the fixup/squash/amend! commits on <source> that are not yet on
# <base> — the corrections a release folds into their targets. Empty when there
# are none.
_fixup_subjects() {
  git log --format='%s' "$1..$2" 2>/dev/null \
    | grep -E '^(fixup|squash|amend)!' || true
}

_fixup_count() {
  local subjects
  subjects="$(_fixup_subjects "$1" "$2")"
  if [[ -z "${subjects}" ]]; then
    printf '0\n'
  else
    printf '%s\n' "${subjects}" | grep -c .
  fi
}

# Folds every fixup/squash/amend! commit not yet on the default branch into its
# target, so a release tag never freezes a commit that only ever corrected an
# earlier one. No fixups means no rebase — the branch's commit ids survive.
# On failure the rebase is aborted and the branch is left as it was.
_squash_fixups() {
  local source="$1" default_branch="$2" base count
  base="$(_default_base_ref "${default_branch}")"
  count="$(_fixup_count "${base}" "${source}")"
  [[ "${count}" -gt 0 ]] || return 0

  if ! GIT_SEQUENCE_EDITOR=: git rebase --quiet --interactive --autosquash "${base}" >/dev/null; then
    git rebase --abort >/dev/null 2>&1 || true
    _fatal "merge: could not squash the fixup commits on '${source}'"
  fi
  printf 'squashed %s fixup commit(s) on %s\n' "${count}" "${source}"
}

# "host path" for a remote URL, empty when the URL carries no repository (a
# local path remote has no host and therefore no slug).
_remote_parts() {
  local url host path
  url="$(git remote get-url "$1" 2>/dev/null || true)"
  [[ -n "${url}" ]] || return 0

  case "${url}" in
    *://*)
      url="${url#*://}"
      url="${url#*@}"
      case "${url}" in
        */*)
          host="${url%%/*}"
          path="${url#*/}"
          ;;
        *) return 0 ;;
      esac
      ;;
    *@*:*)
      url="${url#*@}"
      case "${url}" in
        *:*)
          host="${url%%:*}"
          path="${url#*:}"
          ;;
        *) return 0 ;;
      esac
      ;;
    *) return 0 ;;
  esac

  host="${host%%:*}"
  # A scheme with no host (file://) names no repository, so it has no slug.
  [[ -n "${host}" ]] || return 0
  path="${path%.git}"
  [[ "${path}" == */* ]] || return 0
  printf '%s %s\n' "${host}" "${path}"
}

_remote_slug() {
  local host slug
  read -r host slug < <(_remote_parts "$1") || true
  printf '%s\n' "${slug:-}"
}

_remote_supports_releases() {
  local host slug
  read -r host slug < <(_remote_parts "$1") || true
  [[ "${host}" == "github.com" ]] || return 1
  command -v "${RELEASE_GH}" >/dev/null 2>&1 || return 1
  return 0
}

# ── argument parsing ─────────────────────────────────────────────────────────

# Sets: VERSION, NOTES, REMOTES, SOURCE, DEFAULT_BRANCH (all optional).
# $1 is the subcommand name, used in error messages.
_parse_common() {
  local sub="$1"
  shift
  VERSION=""
  NOTES=""
  REMOTES=""
  SOURCE=""
  DEFAULT_BRANCH=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        VERSION="$2"
        shift 2
        ;;
      --notes-file)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        NOTES="$2"
        shift 2
        ;;
      --remotes)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        REMOTES="$2"
        shift 2
        ;;
      --source)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        SOURCE="$2"
        shift 2
        ;;
      --default | --branch)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        DEFAULT_BRANCH="$2"
        shift 2
        ;;
      *)
        _fatal "$sub: unknown argument '$1'"
        ;;
    esac
  done
}

_remotes_to_use() {
  if [[ -n "${REMOTES}" ]]; then
    local r out=""
    for r in ${REMOTES//,/ }; do out="${out} ${r}"; done
    printf '%s\n' "${out# }"
  else
    git remote
  fi
}

# $1 is the subcommand name, used in error messages.
_resolve_version() {
  local sub="$1"
  shift
  [[ -n "${VERSION}" ]] || _fatal "$sub: --version is required"
  local normalised
  normalised="$(_normalise_version "${VERSION}")" || _fatal "not a valid version: '${VERSION}' (expected X.Y or X.Y.Z, or X.Y.Z.W when the major is 0)"
  printf '%s\n' "${normalised}"
}
