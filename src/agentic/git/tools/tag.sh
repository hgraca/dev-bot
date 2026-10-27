#!/usr/bin/env bash
# =============================================================================
# src/agentic/git/tools/tag.sh
#
# Deterministic half of the `devbot:git-tag` skill. Every subcommand is
# non-interactive; the approval gate lives in the skill, not here.
#
#   version  — resolve the version to tag (remote's newest tag, or validate)
#   plan     — print the tag approval preview (read-only, mutates nothing)
#   merge    — squash the branch's fixups, then merge it into the default branch
#   tag      — create the annotated tag from the notes file
#   push     — push the default branch and the tag to the chosen remotes
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
# The skill documents running this tool with DEV_BOT_ROOT unset; derive it from
# the checkout that holds the script before the shared config helpers use it.
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${_GIT_SH_DIR}/../../../.." && pwd)}"
export DEV_BOT_ROOT
# Sourced first: the shared helpers define a non-exiting `_fatal`, and git.sh's
# exiting version must win.
# shellcheck source=../functions.sh
source "${_GIT_SH_DIR}/../functions.sh"
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

# Resolve a tag-only --ref to a commit. A remote-tracking ref (`origin/main`)
# is read from the remote itself with `ls-remote` — read-only, no ref writes —
# so a local tracking ref that predates a remote merge cannot advertise the
# pre-merge commit as the release target.
_resolve_tag_only_ref() {
  local ref="$1"
  local remote branch sha

  case "${ref}" in
    */*)
      remote="${ref%%/*}"
      branch="${ref#*/}"
      if git remote get-url "${remote}" >/dev/null 2>&1; then
        # `|| sha=""`: under `set -e`/pipefail a failed ls-remote (unreachable
        # remote) would exit here, hiding the actionable diagnostic below.
        sha="$(git ls-remote "${remote}" "refs/heads/${branch}" 2>/dev/null | cut -f1)" || sha=""
        [[ -n "${sha}" ]] \
          || _fatal "plan: cannot verify '${ref}' on '${remote}' — fetch it, or pass the commit SHA"
        printf '%s\n' "${sha}"
        return 0
      fi
      ;;
  esac

  git rev-parse --verify --quiet "${ref}^{commit}" \
    || _fatal "plan: cannot resolve --ref '${ref}'"
}

cmd_plan() {
  _parse_common plan "$@"
  if [[ "${TAG_ONLY}" -ne 1 && -n "${REF}" ]]; then
    _fatal "plan: --ref applies only with --tag-only (the normal plan tags the merged HEAD)"
  fi

  local version
  version="$(_resolve_version plan)"

  local remotes
  remotes="$(_remotes_to_use)"

  # Tag-only: the release commit is already on the remote (the PR is merged),
  # so there is no source branch to merge and no branch to push. Only the tag
  # travels — the safe case on a protected default branch.
  if [[ "${TAG_ONLY}" -eq 1 ]]; then
    local ref="${REF:-HEAD}"
    local ref_commit
    ref_commit="$(_resolve_tag_only_ref "${ref}")"
    local ref_subject="(not fetched locally — run git fetch before tagging)"
    if git cat-file -e "${ref_commit}^{commit}" 2>/dev/null; then
      ref_subject="$(git log -1 --format=%s "${ref_commit}")"
    fi

    printf '## Tag plan\n\n'
    printf -- '- **Version:** `%s`\n' "${version}"
    printf -- '- **Tag:** `%s` (annotated)\n' "${version}"
    printf -- '- **Target:** `%s` %s\n' "${ref_commit}" "${ref_subject}"
    printf -- '- **Branch push:** none (tag only)\n'

    printf '\n### Remotes\n\n'
    for remote in ${remotes}; do
      printf -- '- `%s`\n' "${remote}"
    done

    printf '\n### Tag description\n\n'
    if [[ -n "${NOTES}" ]]; then
      [[ -f "${NOTES}" ]] || _fatal "plan: notes file not found: ${NOTES}"
      printf '```text\n'
      cat "${NOTES}"
      printf '```\n'
    else
      printf '(no notes)\n'
    fi

    printf '\n### What happens on approval\n\n'
    printf '1. Create the annotated tag `%s` at `%s`:\n' "${version}" "${ref_commit}"
    printf '   `tag.sh tag --tag-only --version %s --ref %s --notes-file <notes>`\n' \
      "${version}" "${ref_commit}"
    printf '2. Push only `%s` to:%s.\n' "${version}" \
      "$(for r in ${remotes}; do printf ' `%s' "${r}"; done)"
    printf '\n_No VCS change has been made yet._\n'
    return 0
  fi

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

  local remote

  printf '## Tag plan\n\n'
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
    printf -- '- `%s`\n' "${remote}"
  done

  printf '\n### Tag description\n\n'
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
  printf '\n_No VCS change has been made yet._\n'
}

# ── merge ────────────────────────────────────────────────────────────────────

# Undoes a failed merge so the trap can leave the repository exactly as the user
# had it — never half-merged, never on the wrong branch.
_restore_branch() {
  git merge --abort >/dev/null 2>&1 || true
  if [[ -n "${2:-}" ]]; then
    git switch --quiet --detach "$2" >/dev/null 2>&1 || true
  else
    git switch --quiet "$1" >/dev/null 2>&1 || true
  fi
}

cmd_merge() {
  _parse_common merge "$@"
  if [[ "${TAG_ONLY}" -eq 1 || -n "${REF}" ]]; then
    _fatal "merge: --tag-only/--ref do not apply — merge has a source branch to fold in"
  fi

  local source="${SOURCE:-$(git branch --show-current)}"
  [[ -n "${source}" ]] || _fatal "merge: cannot determine the source branch (detached HEAD)"

  # `plan` deliberately does not do this — refreshing the remote-tracking HEAD
  # writes a ref. Merge may mutate, so it resolves the default branch itself.
  git remote set-head origin --auto >/dev/null 2>&1 || true
  local default_branch="${DEFAULT_BRANCH:-$(_default_branch)}"

  [[ -z "$(git status --porcelain)" ]] || _fatal "merge: the working tree is not clean"

  git fetch --tags --quiet || _fatal "merge: git fetch failed"
  # The vault guards compare against origin/<default>; a stale ref would hide a
  # commit the merge then pulls in.
  git fetch --quiet origin "${default_branch}" \
    || _fatal "merge: could not fetch origin/${default_branch} — cannot verify its memory-vault commits"
  # Pin the exact commit that was checked: a second fetch (`pull`) could bring a
  # vault commit in after the guard and publish it.
  local checked_default=""
  if git rev-parse --verify --quiet "refs/remotes/origin/${default_branch}" >/dev/null; then
    checked_default="$(git rev-parse "refs/remotes/origin/${default_branch}")"
  fi
  [[ -n "${checked_default}" ]] \
    || _fatal "merge: origin/${default_branch} is unavailable — cannot verify its memory-vault commits"

  local source_wt default_wt current_root
  source_wt="$(git worktree list --porcelain \
    | awk -v b="refs/heads/${source}" '$1 == "worktree" { p = substr($0, index($0, " ") + 1) } $1 == "branch" && $2 == b { print p; exit }')"
  default_wt="$(git worktree list --porcelain \
    | awk -v b="refs/heads/${default_branch}" '$1 == "worktree" { p = substr($0, index($0, " ") + 1) } $1 == "branch" && $2 == b { print p; exit }')"
  current_root="$(git rev-parse --show-toplevel)"
  # The merge has to happen where the default branch lives; a checkout that
  # holds it elsewhere cannot be switched out from under its worktree.
  if [[ -n "${default_wt}" && "${default_wt}" != "${current_root}" ]]; then
    _fatal "merge: ${default_branch} is checked out at '${default_wt}' — run this from that checkout"
  fi

  local original_branch original_head
  original_branch="$(git branch --show-current)"
  original_head="$(git rev-parse HEAD)"
  # A detached start must be restored to its commit, not to a branch name. The
  # EXIT trap outlives this frame, so the value lives in a global.
  DETACHED_HEAD=""
  [[ -n "${original_branch}" ]] || DETACHED_HEAD="${original_head}"
  MERGE_SOURCE="${original_branch:-${source}}"
  trap '_restore_branch "${MERGE_SOURCE}" "${DETACHED_HEAD}"' EXIT

  # The guards and the squash read the source tree: use its worktree when it is
  # already checked out elsewhere, otherwise switch to it.
  if [[ -n "${source_wt}" ]]; then
    source_root="${source_wt}"
  else
    git switch --quiet "${source}" \
      || _fatal "merge: could not check out '${source}'"
    source_root="$(git rev-parse --show-toplevel)"
  fi

  # A dirty source worktree would be squashed and merged without its changes.
  [[ -z "$(git -C "${source_root}" status --porcelain)" ]] \
    || _fatal "merge: the source worktree '${source_root}' has uncommitted changes"

  # A stale source tip would release a default branch that omits a PR commit.
  # Query origin directly: a deleted or never-fetched tracking ref must not skip
  # the check. Exit 2 is a confirmed absence; anything else is a query error.
  local source_head="" remote_source="" ls_rc=0
  if [[ "${source}" != "${default_branch}" ]]; then
    git ls-remote --exit-code --heads origin "${source}" >/dev/null 2>&1 || ls_rc=$?
    if [[ "${ls_rc}" -eq 0 ]]; then
      git fetch --quiet origin "${source}" \
        || _fatal "merge: could not fetch origin/${source}"
      source_head="$(git -C "${source_root}" rev-parse HEAD)"
      remote_source="$(git rev-parse "refs/remotes/origin/${source}")" \
        || _fatal "merge: cannot resolve origin/${source} after fetching it"
      [[ "${source_head}" == "${remote_source}" ]] \
        || _fatal "merge: local '${source}' does not match origin/${source}; reconcile before releasing"
    elif [[ "${ls_rc}" -ne 2 ]]; then
      _fatal "merge: cannot query origin for '${source}' — refusing to guess its head"
    fi
  fi

  # `.devbot.project.jsonc` is gitignored and absent from a linked worktree, so
  # a custom devbot_dir there lives in the main checkout. Prefer a source-tree
  # config when present (a tracked one), else the main checkout's copy.
  local config_root="${source_root}" main_root
  if [[ ! -f "${config_root}/.devbot.project.jsonc" ]]; then
    main_root="$(git worktree list --porcelain \
      | awk 'NR == 1 && $1 == "worktree" { print substr($0, index($0, " ") + 1); exit }')"
    if [[ -n "${main_root}" && -f "${main_root}/.devbot.project.jsonc" ]]; then
      config_root="${main_root}"
    fi
  fi

  local vet_root devbot_dir project_config global_config vault_base vault_paths
  vet_root="${config_root}"
  project_config="${vet_root}/.devbot.project.jsonc"
  global_config="$(_devbot_global_config 2>/dev/null || true)"
  # The resolver falls back to `.agents` when it cannot read a config, which
  # would make a custom vault invisible to this guard — so an unreadable config
  # is fatal rather than a silent default. Validate only the file that actually
  # supplies devbot_dir: an irrelevant malformed fallback must not block a
  # release whose project config already pins the vault.
  local project_dir_value="" project_pins_dir=0
  if [[ -f "${project_config}" ]]; then
    project_dir_value="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${project_config}" devbot_dir)" \
      || _fatal "merge: cannot read '${project_config}' — refusing to guess the vault path"
    [[ -z "${project_dir_value}" ]] || project_pins_dir=1
  fi
  if [[ "${project_pins_dir}" -eq 0 && -n "${global_config}" && -f "${global_config}" ]] \
    && ! python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${global_config}" devbot_dir >/dev/null 2>&1; then
    _fatal "merge: cannot read '${global_config}' — refusing to guess the vault path"
  fi
  if ! devbot_dir="$(_devbot_get_project_dir "${vet_root}")"; then
    _fatal "merge: cannot resolve the devbot directory for '${vet_root}' — refusing to guess the vault path"
  fi
  # A readable but non-string value (`[]`, `{}`, `null`, a number, a boolean)
  # would build a bogus prefix while a real vault commit slips past.
  case "${devbot_dir}" in
    "" | \[* | \{* | null | None | true | false)
      _fatal "merge: the devbot directory resolved to a non-string ('${devbot_dir}') — refusing to guess the vault path" ;;
  esac
  case "${devbot_dir}" in
    *[!0-9]*) : ;;  # contains something other than digits: a plausible path
    *) _fatal "merge: the devbot directory resolved to a bare number ('${devbot_dir}') — refusing to guess the vault path" ;;
  esac
  vault_base="${checked_default}"
  if ! vault_paths="$(_vault_paths "${vault_base}" "${source}" "${devbot_dir}")"; then
    _fatal "merge: cannot verify memory-vault commits — base '${vault_base}' is unavailable; publish ${default_branch} first"
  fi
  if [[ -n "${vault_paths}" ]]; then
    _fatal "merge: '${source}' carries memory-vault commits; move them to the local default branch, or merge them deliberately:
$(printf '%s\n' "${vault_paths}" | head -5)"
  fi

  # The local default is outside the merge range, but `release push` publishes
  # it — an unpushed vault commit there would ride out with the release. This
  # runs before the same-branch no-op return, which is exactly that case.
  local default_vault_paths=""
  if git rev-parse --verify --quiet "refs/heads/${default_branch}" >/dev/null; then
    if ! default_vault_paths="$(_vault_paths "${vault_base}" "${default_branch}" "${devbot_dir}")"; then
      _fatal "merge: cannot verify memory-vault commits — base '${vault_base}' is unavailable; publish ${default_branch} first"
    fi
    if [[ -n "${default_vault_paths}" ]]; then
      _fatal "merge: the local ${default_branch} carries unpushed memory-vault commits; move or publish them before releasing:
$(printf '%s\n' "${default_vault_paths}" | head -5)"
    fi

    # A fixup already on the local default is outside `_squash_fixups`, which
    # the same-branch no-op return skips — the release push would publish it.
    local local_fixups
    local_fixups="$(_fixup_subjects "${vault_base}" "${default_branch}")"
    if [[ -n "${local_fixups}" ]]; then
      _fatal "merge: the local ${default_branch} carries unsquashed fixup commits; fold them before releasing:
$(printf '%s\n' "${local_fixups}" | head -5)"
    fi

    # Any local commit ahead of the checked remote is published by the merge
    # that follows (and by the release push), whether or not it touches a vault.
    local local_ahead
    local_ahead="$(git rev-list --count "${vault_base}..${default_branch}")"
    if [[ "${local_ahead}" -gt 0 ]]; then
      _fatal "merge: the local ${default_branch} is ${local_ahead} commit(s) ahead of origin/${default_branch}; reconcile it before releasing"
    fi
  fi

  if [[ "${source}" == "${default_branch}" ]]; then
    # Behind, not ahead (the ahead case is rejected above): the next `tag` would
    # otherwise tag a stale local tip instead of the fetched release.
    git merge --ff-only --quiet "${checked_default}" >/dev/null 2>&1 \
      || _fatal "merge: the local ${default_branch} cannot fast-forward to origin/${default_branch}"
    printf 'already on %s — nothing to merge\n' "${default_branch}"
    return 0
  fi

  # A vault-shaped path under another dot-rooted state dir is caught by
  # `_vault_paths`; a tracked project-config change is reported here.
  local config_changed
  if ! config_changed="$(git log --format= --name-only "${checked_default}..${source}" 2>/dev/null \
    | awk '$0 == ".devbot.project.jsonc" { found=1 } END { print found ? 1 : 0 }')"; then
    config_changed=1
  fi
  [[ "${config_changed}" == "0" ]] \
    || _fatal "merge: the release range changes .devbot.project.jsonc — resolve the vault path for each change first"

  # Squash against the commit the guards verified, not a ref that may have moved.
  if [[ -n "${source_wt}" ]]; then
    ( cd "${source_wt}" && _squash_fixups "${source}" "${default_branch}" "${checked_default}" ) \
      || _fatal "merge: could not squash '${source}' in its worktree"
  else
    _squash_fixups "${source}" "${default_branch}" "${checked_default}"
  fi

  # The PR branch must not move while we rewrite: re-verify the pinned head.
  if [[ -n "${remote_source}" ]]; then
    git fetch --quiet origin "${source}" \
      || _fatal "merge: could not re-fetch origin/${source}"
    [[ "$(git rev-parse "refs/remotes/origin/${source}")" == "${source_head}" ]] \
      || _fatal "merge: origin/${source} moved during the squash; reconcile and retry"
  fi

  # Pin the rewritten source too: another worktree could commit there while we
  # merge. Merge the exact commit that was scanned, not the movable branch ref.
  local squashed_sha
  squashed_sha="$(git -C "${source_root}" rev-parse HEAD)"

  # When the local default branch does not exist yet, this creates it. If the
  # merge fails, the trap restores the branch you started on but that new branch
  # stays behind, sitting at the same commit as origin/<default> — harmless, and
  # deliberately not deleted: removing a branch is a more destructive act than
  # the residue it would clean up.
  git switch --quiet "${default_branch}" 2>/dev/null \
    || git switch --quiet -c "${default_branch}" "origin/${default_branch}" \
    || _fatal "merge: could not switch to '${default_branch}'"

  if [[ -n "${checked_default}" ]]; then
    git merge --ff-only --quiet "${checked_default}" \
      || _fatal "merge: could not fast-forward '${default_branch}' to the checked remote commit"
  else
    _warn "origin/${default_branch} is not present — merging into the local branch as-is"
  fi

  [[ "$(git rev-parse "refs/heads/${source}")" == "${squashed_sha}" ]] \
    || _fatal "merge: '${source}' moved during the release; reconcile and retry"

  if ! git merge --no-edit "${squashed_sha}" >/dev/null; then
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

  # --ref tags an already-merged commit (e.g. origin/main) without checking it
  # out — the local default branch may be ahead or diverged. In tag-only mode it
  # must be the full SHA the plan approved: a branch ref can advance between the
  # approval and this call, and the tag would land on an unapproved commit.
  local ref="${REF:-HEAD}"
  if [[ "${TAG_ONLY}" -ne 1 && -n "${REF}" ]]; then
    _fatal "tag: --ref applies only with --tag-only (the normal tag runs on the merged HEAD)"
  fi
  if [[ "${TAG_ONLY}" -eq 1 ]]; then
    # Full-SHA form first: rev-parse would reject an unfetched approved commit
    # with a generic error and hide the fetch remediation below.
    case "${ref}" in
      *[!0-9a-f]* | "") _fatal "tag: --tag-only needs the full commit SHA from the plan, not '${ref}'" ;;
    esac
    # Object-id length is repository-defined (40 for SHA-1, 64 for SHA-256):
    # derive it instead of assuming SHA-1.
    local native_head
    native_head="$(git rev-parse --verify HEAD 2>/dev/null || true)"
    [[ -n "${native_head}" ]] \
      || _fatal "tag: cannot determine this repository's object-id length"
    [[ ${#ref} -eq ${#native_head} ]] \
      || _fatal "tag: --tag-only needs the full commit SHA from the plan, not '${ref}'"
    git cat-file -e "${ref}^{commit}" 2>/dev/null \
      || _fatal "tag: '${ref}' is not in this checkout — fetch the release branch first"
  fi
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null \
    || _fatal "tag: cannot resolve --ref '${ref}'"

  # Tag the resolved commit, never the original ref: an annotated tag passed as
  # --ref would otherwise create a nested tag instead of one on the release
  # commit.
  local ref_commit
  ref_commit="$(git rev-parse --verify "${ref}^{commit}")"

  # --cleanup=whitespace is load-bearing: the default cleanup strips lines
  # starting with '#' and would silently drop the notes' markdown heading.
  git tag -a "${version}" "${ref_commit}" --cleanup=whitespace -F "${NOTES}" \
    || _fatal "could not create tag ${version}"

  printf 'created tag %s at %s\n' "${version}" "${ref_commit}"
}

# ── default-branch protection ────────────────────────────────────────────────

# True when the remote's default branch requires a pull request (or any ruleset that
# rejects a direct push). Best-effort: no gh, no network or no permission means "unknown",
# which is treated as unprotected so the release can still run offline.
_branch_is_protected() {
  local remote="$1" branch="$2" repo
  command -v gh >/dev/null 2>&1 || return 1
  repo="$(git remote get-url "${remote}" 2>/dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
  [[ -n "${repo}" ]] || return 1
  gh api "repos/${repo}/branches/${branch}/protection" >/dev/null 2>&1
}

# ── push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  _parse_common push "$@"

  local version
  version="$(_resolve_version push)"
  [[ -n "${REMOTES}" ]] || _fatal "push: --remotes is required"
  [[ -z "${REF}" ]] || _fatal "push: --ref does not apply — push sends a created tag"
  local branch="${DEFAULT_BRANCH:-$(_default_branch)}"

  local failed="" remote
  for remote in ${REMOTES//,/ }; do
    if [[ "${TAG_ONLY}" -eq 1 ]]; then
      if git push --quiet "${remote}" "refs/tags/${version}"; then
        printf 'pushed tag %s to %s\n' "${version}" "${remote}"
      else
        failed="${failed} ${remote}"
        _error "could not push tag ${version} to '${remote}'"
      fi
      continue
    fi
    # A protected default branch must move through a PR, never through this command. The
    # tag is unaffected: after the PR is merged the branch is already in sync, so the
    # check passes and only the tag is sent.
    local remote_ref local_ref
    remote_ref="$(git rev-parse --verify --quiet "refs/remotes/${remote}/${branch}" || true)"
    local_ref="$(git rev-parse --verify --quiet "refs/heads/${branch}" || true)"
    if [[ -n "${remote_ref}" && -n "${local_ref}" && "${remote_ref}" != "${local_ref}" ]] \
      && _branch_is_protected "${remote}" "${branch}"; then
      _error "push: '${branch}' on '${remote}' is protected — this push would bypass its rules."
      _error "remediation: push the source branch and merge it through a pull request,"
      _error "  then re-run this push; it will send only the tag:"
      _error "    git push ${remote} <source-branch>"
      _error "    gh pr create --base ${branch} --head <source-branch>"
      _error "    gh pr merge <pr> --rebase   # or --squash, per the repo's convention"
      _fatal "push: refusing to update a protected '${branch}' directly"
    fi

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
    if [[ "${TAG_ONLY}" -eq 1 ]]; then
      _error "remediation: git push <remote> refs/tags/${version}"
    else
      _error "remediation: git push <remote> ${branch} && git push <remote> refs/tags/${version}"
    fi
    exit 1
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────

_usage() {
  cat <<'EOF'
Usage: tag.sh <subcommand> [options]

Subcommands:
  version  [--version V] [--remote R]                     resolve the version to tag
  plan     --version V [--notes-file F] [--remotes a,b]   print the approval preview
  merge    [--source B] [--default D]                      squash fixups, then merge into the default branch
  tag      --version V --notes-file F                      create the annotated tag (normal flow)
  tag      --tag-only --version V --ref R --notes-file F   tag an already-merged commit R
  push     --version V [--branch B] --remotes a,b [--tag-only]
                                                           push the branch and the tag
                                                           (--tag-only: the tag alone)

Already-merged release (tag only, no branch push):
  plan --tag-only --version V --ref R --notes-file F --remotes a,b
  tag  --tag-only --version V --ref R --notes-file F
  push --tag-only --version V --remotes a,b

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
    "" | -h | --help) _usage ;;
    *) _fatal "unknown subcommand '${sub}'" ;;
  esac
}

main "$@"
