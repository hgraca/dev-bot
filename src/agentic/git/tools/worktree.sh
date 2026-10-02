#!/usr/bin/env bash
# ---
# description: Isolate a task's commits in a linked git worktree under <devbot_dir>/worktrees, based on the remote default branch; a project opts out with "worktrees": false
# ---
# =============================================================================
# src/agentic/git/tools/worktree.sh
# Deterministic half of the worktree-per-task policy. An agent runs every
# subcommand from the main checkout; the tool never switches the main
# checkout's checked-out branch, and every worktree is cut from the *remote*
# default branch, not from whatever the main checkout happens to be on.
#
#   create <branch>  — add a worktree under <devbot_dir>/worktrees/<slug>, on a
#                      new untracked branch <branch> based on origin/<default>.
#                      Prints the worktree path (stdout). Refused when the
#                      project set `"worktrees": false`.
#   enabled          — print true/false and exit 0/1 for the worktrees setting.
#   list             — list the worktrees under <devbot_dir>/worktrees.
#   merge  <branch>  — plain merge <branch> into the local default branch.
#                      Requires the main checkout already on the default branch.
#   remove <branch>  — remove the worktree for <branch>. The branch ref stays.
#
# GATE: Linux and macOS. bash 3.2-safe, no GNU-only tools. git >= 2.23.
# =============================================================================

set -euo pipefail

# Resolve through symlinks (the tool is exposed via the .agents/ farm).
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SCRIPT_SOURCE}" ]]; do
  _link_dir="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  [[ "${SCRIPT_SOURCE}" != /* ]] && SCRIPT_SOURCE="${_link_dir}/${SCRIPT_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"

# shellcheck source=../functions.sh
source "${SCRIPT_DIR}/../functions.sh"

DEFAULT_REMOTE="origin"

_fatal() { echo "FATAL: $*" >&2; exit 1; }
_error() { echo "ERROR: $*" >&2; }
_warn() { echo "WARN: $*" >&2; }

# ── git plumbing helpers ─────────────────────────────────────────────────────

# The main checkout's root — the first `worktree list` entry, so the tool
# behaves the same when invoked from inside a linked worktree.
_git_root() {
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1 || true
}

# `<devbot_dir>` for the given project root (default `.agents`).
_devbot_dir_for() {
  _devbot_get_project_dir "$1"
}

# Name of the remote's default branch, resolved without writing any local ref.
# `ls-remote --symref` asks the remote directly; the local remote-tracking HEAD
# and the conventional names are fallbacks for a remote that exposes neither.
_remote_default() {
  local root="$1" name
  name="$(git -C "${root}" ls-remote --symref "${DEFAULT_REMOTE}" HEAD 2>/dev/null \
    | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' \
    | head -1 || true)"
  if [[ -z "${name}" ]]; then
    name="$(git -C "${root}" symbolic-ref --short "refs/remotes/${DEFAULT_REMOTE}/HEAD" 2>/dev/null || true)"
    name="${name#${DEFAULT_REMOTE}/}"
  fi
  if [[ -z "${name}" ]]; then
    if git -C "${root}" rev-parse --verify --quiet "refs/remotes/${DEFAULT_REMOTE}/main" >/dev/null; then
      name="main"
    else
      name="master"
    fi
  fi
  printf '%s\n' "${name}"
}

# Branch name → a filesystem-safe slug: every char outside [A-Za-z0-9._-]
# becomes '-', so `feat/add-login` lands in `feat-add-login/`.
_slug() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9._-]#-#g'
}

# Keep the worktree directory out of `git status` — it lives inside the main
# checkout, so without this every worktree reads as untracked noise.
_ensure_ignored() {
  local root="$1" devbot_dir="$2" gitdir exclude
  gitdir="$(git -C "${root}" rev-parse --absolute-git-dir)"
  exclude="${gitdir}/info/exclude"
  _upsert_gitignore_section "${exclude}" \
    "# >>> DEVBOT - worktrees" \
    "# <<< DEVBOT - worktrees" \
    "${devbot_dir}/worktrees/"
}

# Worktrees are the default way of working; a project (or the global config)
# opts out with `"worktrees": false`. Only an explicit false disables them.
_worktrees_enabled() {
  local root="$1" value
  value="$(_devbot_get_config "worktrees" "${root}")"
  [[ "${value}" != "false" ]]
}

# ── create ───────────────────────────────────────────────────────────────────

cmd_create() {
  local branch="${1:-}"
  [[ -n "${branch}" ]] || _fatal "create: <branch> is required"

  local root devbot_dir default slug path
  root="$(_git_root)"
  [[ -n "${root}" ]] || _fatal "create: not inside a git repository"
  if ! _worktrees_enabled "${root}"; then
    _fatal "create: worktrees are disabled for this project (\"worktrees\": false) — commit in the main checkout"
  fi
  devbot_dir="$(_devbot_dir_for "${root}")"
  default="$(_remote_default "${root}")"
  [[ -n "${default}" ]] || _fatal "create: could not resolve the remote default branch"

  slug="$(_slug "${branch}")"
  path="${root}/${devbot_dir}/worktrees/${slug}"

  [[ ! -e "${path}" ]] || _fatal "create: worktree path already exists: ${path}"
  if git -C "${root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    _fatal "create: branch already exists: ${branch}"
  fi

  if [[ -n "$(git -C "${root}" status --porcelain)" ]]; then
    _warn "create: the main checkout has uncommitted changes — proceeding; commit them in this worktree"
  fi

  _ensure_ignored "${root}" "${devbot_dir}"

  git -C "${root}" fetch --quiet "${DEFAULT_REMOTE}" || _fatal "create: git fetch failed"
  git -C "${root}" worktree add --quiet --no-track -b "${branch}" "${path}" \
    "${DEFAULT_REMOTE}/${default}" \
    || _fatal "create: could not create the worktree"

  printf '%s\n' "${path}"
}

# ── enabled ──────────────────────────────────────────────────────────────────

# Source of truth for the opt-out: prints `true`/`false`, exits 0 when enabled
# (the default) and 1 when the project disabled worktrees.
cmd_enabled() {
  local root
  root="$(_git_root)"
  [[ -n "${root}" ]] || _fatal "enabled: not inside a git repository"

  if _worktrees_enabled "${root}"; then
    printf 'true\n'
  else
    printf 'false\n'
    return 1
  fi
}

# ── list ─────────────────────────────────────────────────────────────────────

cmd_list() {
  local root devbot_dir prefix
  root="$(_git_root)"
  [[ -n "${root}" ]] || _fatal "list: not inside a git repository"
  devbot_dir="$(_devbot_dir_for "${root}")"
  prefix="${root}/${devbot_dir}/worktrees/"

  git -C "${root}" worktree list --porcelain | awk -v prefix="${prefix}" '
    /^worktree / { path = substr($0, 10); branch = "" }
    /^branch /   { branch = substr($0, 8); sub("^refs/heads/", "", branch) }
    /^$/         { if (index(path, prefix) == 1) print path, branch; path = ""; branch = "" }
    END          { if (index(path, prefix) == 1) print path, branch }
  '
}

# ── merge ────────────────────────────────────────────────────────────────────

cmd_merge() {
  local branch="${1:-}"
  [[ -n "${branch}" ]] || _fatal "merge: <branch> is required"

  local root default current
  root="$(_git_root)"
  [[ -n "${root}" ]] || _fatal "merge: not inside a git repository"
  default="$(_remote_default "${root}")"
  current="$(git -C "${root}" branch --show-current)"

  if [[ "${current}" != "${default}" ]]; then
    _fatal "merge: the main checkout is on '${current}', not '${default}' — switch it to '${default}' first (this tool never switches it)"
  fi

  # Checked first so an FF failure below genuinely means divergence, not a
  # dirty tree that would have blocked the checkout.
  [[ -z "$(git -C "${root}" status --porcelain)" ]] \
    || _fatal "merge: the working tree is not clean"

  git -C "${root}" fetch --quiet "${DEFAULT_REMOTE}" || _fatal "merge: git fetch failed"

  # Bring the local default up to the remote before integrating, so the merge
  # is a clean fast-forward. A diverged local default is the human's to rebase.
  if git -C "${root}" rev-parse --verify --quiet "refs/remotes/${DEFAULT_REMOTE}/${default}" >/dev/null; then
    if ! git -C "${root}" merge --ff-only --quiet "${DEFAULT_REMOTE}/${default}" >/dev/null 2>&1; then
      _fatal "merge: '${default}' has diverged from ${DEFAULT_REMOTE}/${default} — rebase it onto ${DEFAULT_REMOTE}/${default} first"
    fi
  fi

  if ! git -C "${root}" merge --no-edit "${branch}" >/dev/null; then
    _error "merge of '${branch}' into '${default}' failed — conflicting paths:"
    git -C "${root}" --no-pager diff --name-only --diff-filter=U >&2 || true
    git -C "${root}" merge --abort >/dev/null 2>&1 || true
    _fatal "nothing was merged"
  fi

  printf 'merged %s into %s\n' "${branch}" "${default}"
}

# ── remove ───────────────────────────────────────────────────────────────────

cmd_remove() {
  local branch="${1:-}"
  [[ -n "${branch}" ]] || _fatal "remove: <branch> is required"

  local root devbot_dir slug path
  root="$(_git_root)"
  [[ -n "${root}" ]] || _fatal "remove: not inside a git repository"
  devbot_dir="$(_devbot_dir_for "${root}")"
  slug="$(_slug "${branch}")"
  path="${root}/${devbot_dir}/worktrees/${slug}"

  [[ -e "${path}" ]] || _fatal "remove: no worktree at ${path}"

  git -C "${root}" worktree remove "${path}" \
    || _fatal "remove: could not remove ${path} — commit or discard its changes first"

  printf 'removed %s\n' "${path}"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

_usage() {
  cat <<'EOF'
Usage: worktree.sh <subcommand> [options]

Subcommands:
  create <branch>   create a worktree under <devbot_dir>/worktrees/<slug> on a
                    new branch based on origin/<default>; prints the path
                    (refused when the project set "worktrees": false)
  enabled           print true/false and exit 0/1 for the worktrees setting
  list              list the worktrees under <devbot_dir>/worktrees
  merge  <branch>   merge <branch> into the local default branch (plain merge)
  remove <branch>   remove the worktree for <branch> (the branch ref stays)

Requires: git >= 2.23 (git switch, git branch --show-current).
EOF
}

main() {
  local sub="${1:-}"
  shift || true
  case "${sub}" in
    create) cmd_create "$@" ;;
    enabled) cmd_enabled "$@" ;;
    list) cmd_list "$@" ;;
    merge) cmd_merge "$@" ;;
    remove) cmd_remove "$@" ;;
    "" | -h | --help) _usage ;;
    *) _fatal "unknown subcommand '${sub}'" ;;
  esac
}

main "$@"
