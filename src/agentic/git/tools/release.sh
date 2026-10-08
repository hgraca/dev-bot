#!/usr/bin/env bash
# =============================================================================
# src/agentic/git/tools/release.sh
#
# Deterministic half of the `devbot:release` slash command. Every subcommand is
# non-interactive; the approval gate lives in the command, not here.
#
#   version  — resolve the version to release (remote's newest tag, or validate)
#   plan     — print the approval preview (read-only, mutates nothing)
#   merge    — squash the branch's fixups, then merge it into the default branch
#   tag      — create the annotated release tag from the notes file
#   push     — push the default branch and the tag to the chosen remotes
#   release  — publish a GitHub release for the pushed tag
#
# GATE: Linux and macOS. bash 3.2-safe (no ${v,,}, no associative arrays), no
# GNU-only tools (no readlink -f, no sed -i, no sort -V); git's own --sort is
# used for version ordering. Needs git >= 2.23 (`git switch`), and >= 2.18 for
# `git ls-remote --sort`.
#
# stdout is machine-readable for `version` — diagnostics always go to stderr.
# =============================================================================

set -euo pipefail

_GIT_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./git.sh
source "${_GIT_SH_DIR}/git.sh"

# ── version ──────────────────────────────────────────────────────────────────

cmd_version() {
  local remote="${DEFAULT_REMOTE}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        VERSION="$2"
        shift 2
        ;;
      --remote)
        [[ $# -ge 2 ]] || _fatal "$1 needs a value"
        remote="$2"
        shift 2
        ;;
      *) _fatal "version: unknown argument '$1'" ;;
    esac
  done

  if [[ -n "${VERSION:-}" ]]; then
    local normalised
    normalised="$(_normalise_version "${VERSION}")" || _fatal "not a valid version: '${VERSION}' (expected X.Y or X.Y.Z, or X.Y.Z.W when the major is 0)"
    if _tag_exists_on_remote "${remote}" "${normalised}"; then
      _fatal "tag ${normalised} already exists on '${remote}'"
    fi
    printf '%s\n' "${normalised}"
    return 0
  fi

  local last
  last="$(_last_remote_tag "${remote}")"
  [[ -n "${last}" ]] || _fatal "no version tags on remote '${remote}' — pass an explicit version"
  _bump_minor "${last}"
}

# ── plan ─────────────────────────────────────────────────────────────────────

cmd_plan() {
  _parse_common plan "$@"

  local version
  version="$(_resolve_version plan)"

  SOURCE="${SOURCE:-$(git branch --show-current)}"
  [[ -n "${SOURCE}" ]] || _fatal "plan: cannot determine the source branch (detached HEAD)"

  local default_branch="${DEFAULT_BRANCH:-$(_default_branch)}"
  local base_ref
  base_ref="$(_default_base_ref "${default_branch}")"

  local merge_kind="merge commit"
  if git merge-base --is-ancestor "${base_ref}" HEAD 2>/dev/null; then
    merge_kind="fast-forward"
  fi

  local fixup_count
  fixup_count="$(_fixup_count "${base_ref}" "${SOURCE}")"

  local remotes release_remotes remote slug
  remotes="$(_remotes_to_use)"
  release_remotes=""

  printf '## Release plan\n\n'
  printf -- '- **Version:** `%s`\n' "${version}"
  printf -- '- **Tag:** `%s` (annotated)\n' "${version}"
  printf -- '- **Source branch:** `%s`\n' "${SOURCE}"
  printf -- '- **Default branch:** `%s`\n' "${default_branch}"
  printf -- '- **Merge:** %s\n' "${merge_kind}"
  if [[ "${fixup_count}" -eq 0 ]]; then
    printf -- '- **Squash:** none\n'
  else
    printf -- '- **Squash:** %s fixup commit(s) folded into their targets\n' "${fixup_count}"
  fi
  printf -- '- **After the release:** the checkout stays on `%s`\n' "${default_branch}"

  printf '\n### Remotes\n\n'
  for remote in ${remotes}; do
    if _remote_supports_releases "${remote}"; then
      slug="$(_remote_slug "${remote}")"
      printf -- '- `%s` — `%s`, release yes\n' "${remote}" "${slug}"
      release_remotes="${release_remotes} ${remote}"
    else
      slug="$(_remote_slug "${remote}")"
      if [[ -n "${slug}" ]]; then
        _warn "'${remote}' (${slug}) does not support releases — the tag will be pushed without one"
      else
        _warn "'${remote}' has no repository slug — the tag will be pushed without a release"
      fi
      printf -- '- `%s` — no release\n' "${remote}"
    fi
  done

  printf '\n### Tag and release description\n\n'
  if [[ -n "${NOTES}" ]]; then
    [[ -f "${NOTES}" ]] || _fatal "plan: notes file not found: ${NOTES}"
    printf '```text\n'
    cat "${NOTES}"
    printf '```\n'
  else
    printf '(no notes)\n'
  fi

  printf '\n### What happens on approval\n\n'
  if [[ "${fixup_count}" -gt 0 ]]; then
    printf '1. Squash %s fixup commit(s) on `%s`, then merge it into `%s` and switch to it.\n' \
      "${fixup_count}" "${SOURCE}" "${default_branch}"
  else
    printf '1. Merge `%s` into `%s` and switch to it.\n' "${SOURCE}" "${default_branch}"
  fi
  printf '2. Create the annotated tag `%s`.\n' "${version}"
  printf '3. Push `%s` and `%s` to:%s.\n' "${default_branch}" "${version}" \
    "$(for r in ${remotes}; do printf ' `%s`' "${r}"; done)"
  if [[ -n "${release_remotes}" ]]; then
    printf '4. Create the GitHub release `%s` on:%s.\n' "${version}" \
      "$(for r in ${release_remotes}; do printf ' `%s`' "${r}"; done)"
  fi
  printf '\n_No VCS change has been made yet._\n'
}

# ── merge ────────────────────────────────────────────────────────────────────

# Undoes a failed merge so the trap can leave the repository exactly as the user
# had it — never half-merged, never on the wrong branch.
_restore_branch() {
  git merge --abort >/dev/null 2>&1 || true
  git switch --quiet "$1" >/dev/null 2>&1 || true
}

cmd_merge() {
  _parse_common merge "$@"

  local source="${SOURCE:-$(git branch --show-current)}"
  [[ -n "${source}" ]] || _fatal "merge: cannot determine the source branch (detached HEAD)"

  # `plan` deliberately does not do this — refreshing the remote-tracking HEAD
  # writes a ref. Merge may mutate, so it resolves the default branch itself.
  git remote set-head origin --auto >/dev/null 2>&1 || true
  local default_branch="${DEFAULT_BRANCH:-$(_default_branch)}"

  [[ -z "$(git status --porcelain)" ]] || _fatal "merge: the working tree is not clean"

  if [[ "${source}" == "${default_branch}" ]]; then
    printf 'already on %s — nothing to merge\n' "${default_branch}"
    return 0
  fi

  MERGE_SOURCE="${source}"
  trap '_restore_branch "$MERGE_SOURCE"' EXIT

  git fetch --tags --quiet || _fatal "merge: git fetch failed"

  _squash_fixups "${source}" "${default_branch}"

  # When the local default branch does not exist yet, this creates it. If the
  # pull or the merge then fails, the trap restores the source branch but that
  # new branch stays behind, sitting at the same commit as origin/<default> —
  # harmless, and deliberately not deleted: removing a branch is a more
  # destructive act than the residue it would clean up.
  git switch --quiet "${default_branch}" 2>/dev/null \
    || git switch --quiet -c "${default_branch}" "origin/${default_branch}" \
    || _fatal "merge: could not switch to '${default_branch}'"

  if git rev-parse --verify --quiet "refs/remotes/origin/${default_branch}" >/dev/null; then
    git pull --ff-only --quiet origin "${default_branch}" \
      || _fatal "merge: could not fast-forward '${default_branch}' from origin"
  else
    _warn "origin/${default_branch} is not present — merging into the local branch as-is"
  fi

  if ! git merge --no-edit "${source}" >/dev/null; then
    _error "merge of '${source}' into '${default_branch}' failed — conflicting paths:"
    git --no-pager diff --name-only --diff-filter=U >&2 || true
    trap - EXIT
    _restore_branch "${source}"
    _fatal "nothing was tagged"
  fi
  trap - EXIT

  printf 'merged %s into %s\n' "${source}" "${default_branch}"
}

# ── tag ──────────────────────────────────────────────────────────────────────

cmd_tag() {
  _parse_common tag "$@"

  local version
  version="$(_resolve_version tag)"
  [[ -n "${NOTES}" ]] || _fatal "tag: --notes-file is required"
  [[ -f "${NOTES}" ]] || _fatal "tag: notes file not found: ${NOTES}"

  if _tag_exists_locally "${version}"; then
    _fatal "tag ${version} already exists"
  fi

  # --cleanup=whitespace is load-bearing: the default cleanup strips lines
  # starting with '#' and would silently drop the notes' markdown heading.
  git tag -a "${version}" --cleanup=whitespace -F "${NOTES}" \
    || _fatal "could not create tag ${version}"

  printf 'created tag %s\n' "${version}"
}

# ── push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  _parse_common push "$@"

  local version
  version="$(_resolve_version push)"
  [[ -n "${REMOTES}" ]] || _fatal "push: --remotes is required"
  local branch="${DEFAULT_BRANCH:-$(_default_branch)}"

  local failed="" remote
  for remote in ${REMOTES//,/ }; do
    if git push --quiet "${remote}" "${branch}" \
      && git push --quiet "${remote}" "refs/tags/${version}"; then
      printf 'pushed %s and %s to %s\n' "${branch}" "${version}" "${remote}"
    else
      failed="${failed} ${remote}"
      _error "could not push to '${remote}'"
    fi
  done

  if [[ -n "${failed}" ]]; then
    _error "push failed for:${failed}"
    _error "remediation: git push <remote> ${branch} && git push <remote> refs/tags/${version}"
    exit 1
  fi
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
  version  [--version V] [--remote R]                     resolve the version to release
  plan     --version V [--notes-file F] [--remotes a,b]   print the approval preview
  merge    [--source B] [--default D]                      squash fixups, then merge into the default branch
  tag      --version V --notes-file F                      create the annotated tag
  push     --version V [--branch B] --remotes a,b          push the branch and the tag
  release  --version V --notes-file F --remotes a,b        publish GitHub releases

Environment:
  RELEASE_GH   path to the GitHub CLI (default: gh)

Requires: bash; git >= 2.23 (git switch), git >= 2.18 (ls-remote --sort).
EOF
}

main() {
  local sub="${1:-}"
  shift || true
  case "${sub}" in
    version) cmd_version "$@" ;;
    plan) cmd_plan "$@" ;;
    merge) cmd_merge "$@" ;;
    tag) cmd_tag "$@" ;;
    push) cmd_push "$@" ;;
    release) cmd_release "$@" ;;
    "" | -h | --help) _usage ;;
    *) _fatal "unknown subcommand '${sub}'" ;;
  esac
}

main "$@"
