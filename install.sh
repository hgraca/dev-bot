#!/usr/bin/env bash
# =============================================================================
# install.sh
# Direct-install bootstrap for dev-bot. Downloads the dev-bot repository and
# runs the in-repo installer (bin/install.sh), then links the `devbot` CLI
# onto $PATH so it can be used from any project directory.
#
# Usage:
#   curl -fsSL https://get-e.github.io/dev-bot/install.sh | bash -s -- --ssh
#   curl -fsSL <url> | bash -s -- --org <org> --repo <repo> --branch <branch> --host <host> [--ssh]
#   bash install.sh              # from inside a dev-bot clone (used by `make install`)
#
# The repository location is built from pieces so a fork, a mirror, or a moved
# repository can be targeted without editing this file:
#   piece   | flag          | env var             | default
#   --------|---------------|---------------------|------------
#   host    | --host        | DEV_BOT_HOST        | github.com
#   org     | --org         | DEV_BOT_ORG         | GET-E
#   repo    | --repo        | DEV_BOT_REPO        | dev-bot
#   branch  | --branch      | DEV_BOT_BRANCH      | latest release tag, else main
#   ssh     | --ssh         | DEV_BOT_SSH         | false (git@host:org/repo.git)
#   dir     | --install-dir | DEV_BOT_INSTALL_DIR | ~/.local/share/dev-bot
#
# When no branch is given, the latest GitHub release tag is installed when one
# exists; otherwise the repository falls back to its default branch (main).
# =============================================================================

set -euo pipefail

# ── Repo location pieces (flag > env var > literal default) ─────────────────
HOST="${DEV_BOT_HOST:-github.com}"
ORG="${DEV_BOT_ORG:-GET-E}"
REPO="${DEV_BOT_REPO:-dev-bot}"
BRANCH="${DEV_BOT_BRANCH:-}"
BRANCH_SET=false
INSTALL_DIR="${DEV_BOT_INSTALL_DIR:-$HOME/.local/share/dev-bot}"
SSH="${DEV_BOT_SSH:-false}"
PRINT_URL=false

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Downloads the dev-bot repository and installs it, then links the `devbot`
CLI onto $PATH. When run from inside a dev-bot clone (e.g. `make install`),
the current checkout is used and nothing is downloaded.

Options:
  --org <org>          GitHub org (default: GET-E, env: DEV_BOT_ORG)
  --repo <repo>        GitHub repo (default: dev-bot, env: DEV_BOT_REPO)
  --branch <branch>    Git branch to install (default: latest release tag,
                       else main, env: DEV_BOT_BRANCH)
  --host <host>        Git host (default: github.com, env: DEV_BOT_HOST)
  --ssh                Clone over SSH (git@host:org/repo.git) instead of HTTPS
  --install-dir <dir>  Install directory (default: ~/.local/share/dev-bot,
                       env: DEV_BOT_INSTALL_DIR)
  --print-url          Print the computed clone URL and exit (no install)
  -h, --help           Show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; BRANCH_SET=true; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --ssh) SSH=true; shift ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --print-url) PRINT_URL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

# An explicitly-set branch (flag or env) wins over release-tag resolution.
[[ -n "${BRANCH}" ]] && BRANCH_SET=true

if [[ "${SSH}" == true ]]; then
  REPO_URL="git@${HOST}:${ORG}/${REPO}.git"
else
  REPO_URL="https://${HOST}/${ORG}/${REPO}.git"
fi

if [[ "${PRINT_URL}" == true ]]; then
  echo "${REPO_URL}"
  exit 0
fi

# ── Resolve the dev-bot root: in-clone vs standalone ────────────────────────
# When piped via `curl … | bash` (no file), BASH_SOURCE is empty and the [0]
# subscript is unbound under set -u — fall back to PWD.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="${PWD}"
fi
if [[ -f "${PWD}/bin/install.sh" ]]; then
  DEV_BOT_ROOT="${PWD}"
elif [[ -f "${SCRIPT_DIR}/bin/install.sh" ]]; then
  DEV_BOT_ROOT="${SCRIPT_DIR}"
else
  DEV_BOT_ROOT=""
fi

# ── Fetch the latest release tag from the GitHub API ─────────────────────────
# Prints the tag name, or nothing when the repo has no releases / the API is
# unreachable. The trailing `|| true` keeps the pipeline from tripping
# `set -euo pipefail` when curl exits non-zero (e.g. 404) or grep finds no match.
_fetch_latest_release_tag() {
  curl -fsSL "https://api.github.com/repos/${ORG}/${REPO}/releases/latest" 2>/dev/null \
    | grep '"tag_name":' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
    || true
}

if [[ -z "${DEV_BOT_ROOT}" ]]; then
  # Standalone: obtain the repository first.
  if ! command -v git >/dev/null 2>&1; then
    echo "FATAL: git is required but not installed." >&2
    exit 1
  fi

  # Resolve the ref to install: explicit branch > latest release tag > main.
  REF="${BRANCH}"
  REF_IS_TAG=false
  if [[ "${BRANCH_SET}" != true ]]; then
    REF="main"
    TAG="$(_fetch_latest_release_tag)"
    if [[ -n "${TAG}" ]]; then
      REF="${TAG}"
      REF_IS_TAG=true
    else
      echo "WARN: no release tag found for ${ORG}/${REPO} — falling back to main."
    fi
  fi

  INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    if [[ "${REF_IS_TAG}" == true ]]; then
      echo "WARN: ${INSTALL_DIR} already exists — updating to release ${REF}..."
      git -C "${INSTALL_DIR}" fetch origin tag "${REF}"
      git -C "${INSTALL_DIR}" checkout "${REF}"
    else
      echo "WARN: ${INSTALL_DIR} already exists — pulling latest ${REF}..."
      git -C "${INSTALL_DIR}" pull --ff-only origin "${REF}"
    fi
  elif [[ -e "${INSTALL_DIR}" ]] && [[ -n "$(ls -A "${INSTALL_DIR}" 2>/dev/null || true)" ]]; then
    echo "FATAL: ${INSTALL_DIR} exists and is not a dev-bot clone. Move it away or pass --install-dir." >&2
    exit 1
  else
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    echo "INFO: cloning ${REPO_URL} (${REF}) into ${INSTALL_DIR}..."
    git clone --depth 1 --branch "${REF}" "${REPO_URL}" "${INSTALL_DIR}"
  fi
  DEV_BOT_ROOT="${INSTALL_DIR}"
fi

# ── Run the in-repo installer ────────────────────────────────────────────────
echo "INFO: installing from ${DEV_BOT_ROOT}..."
bash "${DEV_BOT_ROOT}/bin/install.sh"

# ── Link the devbot CLI onto $PATH ──────────────────────────────────────────
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
LINK="${BIN_DIR}/devbot"
TARGET="${DEV_BOT_ROOT}/bin/devbot"

if [[ -L "${LINK}" ]]; then
  if [[ "$(readlink "${LINK}")" == "${TARGET}" ]]; then
    echo "OK: ${LINK} already points to ${TARGET}"
  else
    ln -sfn "${TARGET}" "${LINK}"
    echo "OK: relinked ${LINK} -> ${TARGET}"
  fi
elif [[ -e "${LINK}" ]]; then
  echo "WARN: ${LINK} exists and is not a symlink — leaving it alone. Add ${TARGET} to your PATH manually." >&2
else
  ln -s "${TARGET}" "${LINK}"
  echo "OK: linked ${LINK} -> ${TARGET}"
fi

echo
echo "DevBot installed. Run 'devbot --help' to get started."
