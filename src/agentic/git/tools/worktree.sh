#!/usr/bin/env bash
# ---
# description: Isolate a task's commits in a linked git worktree under <devbot_dir>/worktrees, based on the remote default branch; used by the default `worktrees` workflow
# ---
# =============================================================================
# src/agentic/git/tools/worktree.sh
# Deterministic half of the worktree-per-task policy. An agent runs every
# subcommand from the main checkout; the tool never switches the main
# checkout's checked-out branch, and every worktree is cut from the *remote*
# default branch, not from whatever the main checkout happens to be on.
#
#   create <branch> [--base <ref>] [--link <dir>]... [--no-link]
#                    — add a worktree under <devbot_dir>/worktrees/<slug>, on a
#                      new untracked branch <branch> based on --base <ref>
#                      (default: origin/<default>), then hard-link the
#                      dependency dirs listed by --link (default: vendor,
#                      node_modules) from the main checkout. Prints the worktree
#                      path (stdout). Refused when the project follows a
#                      workflow other than `worktrees`.
#   enabled          — print true/false and exit 0/1 for the resolved workflow;
#                      exit 2 when the configured workflow is unknown.
#   list             — list the worktrees under <devbot_dir>/worktrees.
#   path   <branch>  — print the absolute path git registered for <branch>, read
#                      from the registration. The one way to ask.
#   push   <branch>  — push <branch> to origin and set its upstream, so it can
#                      be opened as a pull request. Nothing local is merged.
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
_warn() { echo "WARN: $*" >&2; }

# ── git plumbing helpers ─────────────────────────────────────────────────────

# The main checkout's root — the first `worktree list` entry of the repository
# containing <dir> (default: the current directory), so the tool behaves the
# same when invoked from inside a linked worktree. Naming the project matters in
# a monorepo session, where the session root is a container repository and the
# task belongs to a child.
_git_root() {
  local dir="${1:-.}"
  git -C "${dir}" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1 || true
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

# The path git registered for a *linked* worktree of <branch>
# (full ref accepted too), or nothing. Never rebuilt.
_registered_worktree() {
  local root="$1" branch="$2" listing
  branch="${branch#refs/heads/}"
  # Read the whole listing before matching: an early
  # awk exit would SIGPIPE git under pipefail.
  listing="$(git -C "${root}" worktree list --porcelain)" || return 1
  printf '%s\n' "${listing}" \
    | awk -v want="refs/heads/${branch}" -v main="${root}" '
    /^worktree / { path = substr($0, 10); hit = 0; primary = (path == main) }
    /^branch /   { hit = (substr($0, 8) == want) && !primary }
    /^$/         { if (hit && !done) { print path; done = 1 } }
    END          { if (!done && hit) print path }
  '
}

# A path is ours when its Git dir is this repo's
# <git>/worktrees/<slug> with <branch> checked out.
_is_linked_worktree() {
  local root="$1" branch="$2" path="$3" root_git path_git head
  root_git="$(git -C "${root}" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  path_git="$(git -C "${path}" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  case "${path_git}" in
    "${root_git}/worktrees/"*) ;;
    *) return 1 ;;
  esac
  head="$(git -C "${path}" symbolic-ref --quiet --short HEAD 2>/dev/null)" || return 1
  [[ "${head}" == "${branch}" ]]
}

# The registered path for <branch>, insisting it still exists and is still
# ours: a stale or replaced directory fails later with a bare message.
_worktree_for() {
  local cmd="$1" root="$2" branch="$3" path qroot
  branch="${branch#refs/heads/}"
  path="$(_registered_worktree "${root}" "${branch}")"
  [[ -n "${path}" ]] || _fatal "${cmd}: no worktree is registered for '${branch}'"
  qroot="$(printf '%q' "${root}")"
  if [[ ! -d "${path}" ]]; then
    _fatal "${cmd}: ${path} is registered but gone — drop it with: git -C ${qroot} worktree prune"
  fi
  # prune ignores a registration whose path exists, so a replaced one
  # needs the path moved out of the way first.
  _is_linked_worktree "${root}" "${branch}" "${path}" \
    || _fatal "${cmd}: ${path} is not a live worktree of ${root} — move it aside, then: git -C ${qroot} worktree prune"
  printf '%s\n' "${path}"
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

# The effective workflow — `worktrees` (the default) or `trunk` — including the
# retired-key compatibility and the project-first precedence:
# see `_devbot_get_workflow` in src/_shared/functions.sh.
_workflow() {
  _devbot_get_workflow "$1"
}

# Hard-link the dependency dirs from the main checkout into the fresh worktree,
# so it can build and test without re-installing them. Best-effort: a missing
# source, an existing destination, or a failed copy only warns — the worktree
# stays usable.
_link_deps() {
  local root="$1" wt="$2"
  shift 2
  local dir src dest linked=()
  for dir in "$@"; do
    src="${root}/${dir}"
    dest="${wt}/${dir}"
    if [[ ! -d "${src}" ]]; then
      _warn "create: no ${dir}/ in the main checkout — skipping"
      continue
    fi
    if [[ -e "${dest}" ]]; then
      _warn "create: ${dir}/ already exists in the worktree — skipping"
      continue
    fi
    mkdir -p "$(dirname "${dest}")" 2>/dev/null || true
    if cp -al "${src}" "${dest}" 2>/dev/null; then
      linked+=("${dir}")
    else
      rm -rf "${dest}" 2>/dev/null || true
      _warn "create: could not hard-link ${dir}/ — install dependencies in the worktree instead"
    fi
  done
  if [[ "${#linked[@]}" -gt 0 ]]; then
    _ignore_in_worktree "${wt}" "${linked[@]}"
  fi
}

# A linked dir need not be in the project's .gitignore; ignore it in the
# worktree's own exclude so it never shows as untracked or blocks `remove`.
_ignore_in_worktree() {
  local wt="$1"
  shift
  local exclude dir lines=()
  exclude="$(git -C "${wt}" rev-parse --git-path info/exclude)"
  for dir in "$@"; do
    lines+=("${dir}/")
  done
  _upsert_gitignore_section "${exclude}" \
    "# >>> DEVBOT - linked dependencies" \
    "# <<< DEVBOT - linked dependencies" \
    "${lines[@]}"
}

# A fresh worktree can be briefly unreadable on some
# filesystems; retry, then fail instead of lying.
_await_usable() {
  local path="$1" branch="$2" attempt=0
  until git -C "${path}" rev-parse --show-toplevel >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ "${attempt}" -ge 5 ]]; then
      _fatal "create: ${path} is registered but not readable — the branch and worktree exist; resolve it with: worktree.sh path ${branch}"
    fi
    sleep 0.2
  done
}

# ── create ───────────────────────────────────────────────────────────────────

cmd_create() {
  local branch="" no_link=false base="" project=""
  local links=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        [[ -n "${2:-}" ]] || _fatal "create: --base requires a <ref>"
        base="$2"
        shift 2
        ;;
      --project)
        [[ -n "${2:-}" ]] || _fatal "create: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "create: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      --link)
        [[ -n "${2:-}" ]] || _fatal "create: --link requires a <dir>"
        case "${2}" in
          /*) _fatal "create: --link <dir> must be a relative path, got '${2}'" ;;
        esac
        case "/${2}/" in
          */../*) _fatal "create: --link <dir> must not contain '..', got '${2}'" ;;
        esac
        links+=("$2")
        shift 2
        ;;
      --no-link)
        no_link=true
        shift
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      -*)
        _fatal "create: unknown option '$1'"
        ;;
      *)
        [[ -z "${branch}" ]] || _fatal "create: unexpected argument '$1'"
        branch="$1"
        shift
        ;;
    esac
  done
  [[ -n "${branch}" ]] || _fatal "create: <branch> is required"

  # Defaults apply only when neither --link nor --no-link was given.
  local link_dirs=()
  if [[ "${no_link}" == "true" ]]; then
    link_dirs=()
  elif [[ "${#links[@]}" -gt 0 ]]; then
    link_dirs=("${links[@]}")
  else
    link_dirs=(vendor node_modules)
  fi

  local root devbot_dir default base_ref slug path base_sha
  root="$(_git_root "${project}")"
  [[ -n "${root}" ]] || _fatal "create: not inside a git repository"
  if [[ "$(_devbot_get_config "monorepo" "${root}")" == "true" ]]; then
    _fatal "create: ${root} is a monorepo project, not a codebase — pass --project <owning-project> to create the worktree there"
  fi
  if ! git -C "${root}" rev-parse --verify --quiet HEAD >/dev/null; then
    _fatal "create: ${root} has no commits — make an initial commit before creating a worktree"
  fi
  local workflow
  workflow="$(_workflow "${root}")"
  case "${workflow}" in
    worktrees) ;;
    trunk) _fatal "create: this project follows the trunk workflow — commit on the default branch instead" ;;
    *) _fatal "create: unknown workflow '${workflow}' — known workflows: worktrees, trunk" ;;
  esac
  devbot_dir="$(_devbot_dir_for "${root}")"
  default="$(_remote_default "${root}")"
  [[ -n "${default}" ]] || _fatal "create: could not resolve the remote default branch"
  base_ref="${base:-${DEFAULT_REMOTE}/${default}}"
  [[ "${base_ref}" != -* ]] || _fatal "create: --base must not start with '-'"

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

  # Resolve --base in the INVOKING checkout: HEAD, @ and @{upstream} are
  # per-worktree, so resolving them with -C <root> from a linked worktree would
  # silently pick the main checkout's commit. With --project the caller names
  # the repository explicitly, so the ref resolves there instead.
  local base_cwd="${project:-.}"
  base_sha="$(git -C "${base_cwd}" rev-parse --verify --quiet "${base_ref}^{commit}")" \
    || _fatal "create: --base '${base_ref}' does not resolve to a commit"
  git -C "${root}" worktree add --quiet --no-track -b "${branch}" "${path}" \
    "${base_sha}" \
    || _fatal "create: could not create the worktree"

  _await_usable "${path}" "${branch}"

  if [[ "${#link_dirs[@]}" -gt 0 ]]; then
    _link_deps "${root}" "${path}" "${link_dirs[@]}"
  fi

  printf '%s\n' "${path}"
}

# ── enabled ──────────────────────────────────────────────────────────────────

# Source of truth for the opt-out: prints `true`/`false`, exits 0 when enabled
# (the default) and 1 when the project disabled worktrees.
cmd_enabled() {
  local project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || _fatal "enabled: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "enabled: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      *) _fatal "enabled: unknown argument '$1'" ;;
    esac
  done

  local root
  root="$(_git_root "${project}")"
  [[ -n "${root}" ]] || _fatal "enabled: not inside a git repository"
  if [[ "$(_devbot_get_config "monorepo" "${root}")" == "true" ]]; then
    _fatal "enabled: ${root} is a monorepo project, not a codebase — pass --project <owning-project>"
  fi

  local workflow
  workflow="$(_workflow "${root}")"
  case "${workflow}" in
    worktrees)
      printf 'true\n'
      return 0
      ;;
    trunk)
      printf 'false\n'
      return 1
      ;;
    *)
      # A distinct status: callers must stop and ask, not fall back to trunk.
      printf 'ERROR: unknown workflow %s — known workflows: worktrees, trunk\n' "'${workflow}'" >&2
      return 2
      ;;
  esac
}

# ── list ─────────────────────────────────────────────────────────────────────

cmd_list() {
  local project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || _fatal "list: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "list: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      -*)
        _fatal "list: unknown option '$1'"
        ;;
      *)
        _fatal "list: unexpected argument '$1'"
        ;;
    esac
  done

  local root devbot_dir prefix
  root="$(_git_root "${project}")"
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

# ── path ─────────────────────────────────────────────────────────────────────

# The directory is the branch's slug, so a path built
# from the branch name points at nothing. Ask here.
cmd_path() {
  local branch="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || _fatal "path: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "path: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      -*)
        _fatal "path: unknown option '$1'"
        ;;
      *)
        [[ -z "${branch}" ]] || _fatal "path: unexpected argument '$1'"
        branch="$1"
        shift
        ;;
    esac
  done
  [[ -n "${branch}" ]] || _fatal "path: <branch> is required"

  local root path
  root="$(_git_root "${project}")"
  [[ -n "${root}" ]] || _fatal "path: not inside a git repository"

  path="$(_worktree_for path "${root}" "${branch}")"

  printf '%s\n' "${path}"
}

# ── push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  local branch="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || _fatal "push: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "push: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      -*)
        _fatal "push: unknown option '$1'"
        ;;
      *)
        [[ -z "${branch}" ]] || _fatal "push: unexpected argument '$1'"
        branch="$1"
        shift
        ;;
    esac
  done
  [[ -n "${branch}" ]] || _fatal "push: <branch> is required"

  local root path default
  root="$(_git_root "${project}")"
  [[ -n "${root}" ]] || _fatal "push: not inside a git repository"

  path="$(_worktree_for push "${root}" "${branch}")"

  default="$(_remote_default "${root}")"

  git -C "${path}" push --quiet --set-upstream "${DEFAULT_REMOTE}" "${branch}" \
    || _fatal "push: could not push '${branch}' to ${DEFAULT_REMOTE}"

  printf 'pushed %s to %s/%s\n' "${branch}" "${DEFAULT_REMOTE}" "${branch}"
  printf 'next: open the pull request against %s\n' "${default}"
}

# ── remove ───────────────────────────────────────────────────────────────────

cmd_remove() {
  local branch="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || _fatal "remove: --project requires a <dir>"
        [[ -d "${2}" ]] || _fatal "remove: --project '${2}' is not a directory"
        project="$2"
        shift 2
        ;;
      -h | --help)
        _usage
        return 0
        ;;
      -*)
        _fatal "remove: unknown option '$1'"
        ;;
      *)
        [[ -z "${branch}" ]] || _fatal "remove: unexpected argument '$1'"
        branch="$1"
        shift
        ;;
    esac
  done
  [[ -n "${branch}" ]] || _fatal "remove: <branch> is required"

  local root path
  root="$(_git_root "${project}")"
  [[ -n "${root}" ]] || _fatal "remove: not inside a git repository"

  path="$(_worktree_for remove "${root}" "${branch}")"

  git -C "${root}" worktree remove "${path}" \
    || _fatal "remove: could not remove ${path} — commit or discard its changes first"

  printf 'removed %s\n' "${path}"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

_usage() {
  cat <<'EOF'
Usage: worktree.sh <subcommand> [options]

Subcommands:
  create <branch> [--base <ref>] [--project <dir>] [--link <dir>]... [--no-link]
                    create a worktree under <devbot_dir>/worktrees/<slug> on a
                    new branch based on --base <ref> (default origin/<default>);
                    hard-link the --link dirs (repeatable; default vendor,
                    node_modules) from the main checkout. --no-link disables.
                    --project names the owning project (default: cwd) — required
                    in a monorepo session, whose root has no commits.
                    Prints the path (refused outside the worktrees workflow)
  enabled [--project <dir>]
                    print true/false and exit 0/1 for the resolved workflow;
                    exit 2 when the configured workflow is unknown
  list   [--project <dir>]
                    list the worktrees under <devbot_dir>/worktrees
  path   <branch> [--project <dir>]
                    print the absolute path registered for <branch>; the
                    directory is the branch's slug, so never build it by hand
  push   <branch> [--project <dir>]
                    push <branch> to origin and set its upstream
  remove <branch> [--project <dir>]
                    remove the worktree for <branch> (the branch ref stays)

Every subcommand that needs a repository takes --project <dir>. <branch> is
always the branch name, never the worktree directory name.

Monorepo sessions:
  A monorepo session's root is a container for sibling repositories, so the
  tool resolves the wrong repo unless told which one. Pass the child's main
  checkout as --project and run it from anywhere:

    owner="$(devbot tool project-for-path "$file" --json | jq -r .path)"
    worktree.sh create feat/thing --project "$owner"
    worktree.sh push   feat/thing --project "$owner"
    worktree.sh remove feat/thing --project "$owner"

  create and enabled refuse a monorepo root even when it has commits. Running
  the tool with the child's main checkout as the working directory also works,
  but --project does not depend on where the shell happens to be.

Requires: git >= 2.23.
EOF
}

main() {
  local sub="${1:-}"
  shift || true
  case "${sub}" in
    create) cmd_create "$@" ;;
    enabled) cmd_enabled "$@" ;;
    list) cmd_list "$@" ;;
    path) cmd_path "$@" ;;
    push) cmd_push "$@" ;;
    remove) cmd_remove "$@" ;;
    "" | -h | --help) _usage ;;
    *) _fatal "unknown subcommand '${sub}'" ;;
  esac
}

main "$@"
