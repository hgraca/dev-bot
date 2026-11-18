#!/usr/bin/env bash
# src/agentic/k8s/tools/kctl-mcp.sh
# Launcher for one cluster's kctl MCP server.
#
# Usage: kctl-mcp.sh <cluster>
#
# The per-cluster manifest (published by init.sh) names exactly one catalogue
# cluster, so each server serves one target and its single `kubectl` tool cannot
# reach another. Everything else — the generated kubeconfig, the context, the
# credential preflight — is resolved by kctl.sh at call time.
#
# This script is symlinked into .opencode/ and .claude/ by the harness
# (harness-assets.json) and invoked by that manifest.
set -euo pipefail

# Symlink-safe and GNU-free: resolve the chain by hand. `readlink -f` is
# GNU-only and absent on macOS.
_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${_SOURCE}" ]]; do
  _DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
  _SOURCE="$(readlink "${_SOURCE}")"
  [[ "${_SOURCE}" != /* ]] && _SOURCE="${_DIR}/${_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
MODULE_DIR="$(cd -P "${SCRIPT_DIR}/.." && pwd)"
# Derived from this file's own location, never from the environment: the
# symlink target IS the install that ships this launcher, and an inherited
# DEV_BOT_ROOT could name another checkout (a linked worktree, an old install).
DEV_BOT_ROOT="$(cd -P "${MODULE_DIR}/../../.." && pwd)"
export DEV_BOT_ROOT

CLUSTER="${1:-}"
if [[ -z "${CLUSTER}" ]]; then
  echo "kctl-mcp: usage: kctl-mcp.sh <cluster>" >&2
  exit 1
fi
export KCTL_CLUSTER="${CLUSTER}"

# The project is the directory the harness dir sits in. `$0` resolves through
# the symlink to this module, so ask the link's own directory instead — the same
# resolution the other MCP launchers use. It is always derived, never taken from
# the environment: an inherited value could point the server at another
# project's kubeconfig, which is the boundary this server exists to hold.
SYMLINK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SYMLINK_DIR="$(pwd)"
KCTL_PROJECT_DIR="$(cd "${SYMLINK_DIR}/.." 2>/dev/null && pwd)" || KCTL_PROJECT_DIR="$(pwd)"
export KCTL_PROJECT_DIR

# Resolve bun robustly: the harness's MCP launch may not carry ~/.bun/bin on
# PATH, and a missing PATH makes `exec bun` fail with "bun: not found". The
# server is unavailable, not silently degraded — say so on stderr, where the
# manifest's log file picks it up.
BUN="$(command -v bun 2>/dev/null || true)"
if [[ -z "${BUN}" && -x "${HOME}/.bun/bin/bun" ]]; then
  BUN="${HOME}/.bun/bin/bun"
fi
if [[ -z "${BUN}" ]]; then
  echo "kctl-mcp: bun not found — the kctl MCP server is unavailable (run 'devbot install')" >&2
  exit 1
fi

exec "${BUN}" run "${MODULE_DIR}/server/kctl-mcp.ts"
