#!/usr/bin/env bash
# =============================================================================
# src/agentic/react/init.sh
# Per-project detection for the react module.
# Detects React/Next.js projects and informs about available tooling.
#
# Run by bin/init.sh during devbot init.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

main() {
  _info "react — project initialization"

  # Check if project has a React/Next.js package.json
  local pkg_json="${PROJECT_DIR}/package.json"
  if [[ ! -f "${pkg_json}" ]]; then
    _skip "No package.json found — skipping react init"
    return 0
  fi

  # Check for react or next in dependencies
  if ! python3 -c "
import json, sys
with open('${pkg_json}') as f:
    pkg = json.load(f)
deps = {**pkg.get('dependencies', {}), **pkg.get('devDependencies', {})}
if 'react' in deps or 'next' in deps:
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null; then
    _skip "Not a React/Next.js project — skipping react init"
    return 0
  fi

  _ok "React/Next.js project detected"

  _info "Available tooling for this project:"
  _info "  - next-devtools MCP server  (auto-registered by devbot init via mcp.opencode.json)"
  _info "  - mindrally-react skills    (react patterns, via external-modules.json)"
  _info "  - mindrally-nextjs skills   (Next.js + React + TypeScript, via external-modules.json)"
  _info "  - mindrally-react-best-practices skills (modern web development, via external-modules.json)"
  _info "Run 'devbot init' to register MCP servers and wire external modules."

  _ok "react project initialization complete"
}

main "$@"
