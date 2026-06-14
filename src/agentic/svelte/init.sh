#!/usr/bin/env bash
# =============================================================================
# src/agentic/svelte/init.sh
# Per-project detection for the svelte module.
# Detects Svelte/SvelteKit projects and informs about available tooling.
#
# Run by bin/init.sh during devbot init.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _error "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

main() {
  _info "svelte — project initialization"

  # Check if project has a Svelte/SvelteKit package.json
  local pkg_json="${PROJECT_DIR}/package.json"
  if [[ ! -f "${pkg_json}" ]]; then
    _skip "No package.json found — skipping svelte init"
    return 0
  fi

  # Check for svelte or @sveltejs/kit in dependencies
  if ! python3 -c "
import json, sys
with open('${pkg_json}') as f:
    pkg = json.load(f)
deps = {**pkg.get('dependencies', {}), **pkg.get('devDependencies', {})}
if 'svelte' in deps or '@sveltejs/kit' in deps:
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null; then
    _skip "Not a Svelte/SvelteKit project — skipping svelte init"
    return 0
  fi

  _ok "Svelte/SvelteKit project detected"

  _info "Available tooling for this project:"
  _info "  - @sveltejs/mcp MCP server  (auto-registered by devbot init via mcp.opencode.json)"
  _info "  - mindrally-svelte skills   (svelte patterns, via external-modules.json)"
  _info "  - sveltekit-structure skills (SvelteKit project structure, via external-modules.json)"
  _info "  - svelte5-best-practices skills (Svelte 5 best practices, via external-modules.json)"
  _info "Run 'devbot init' to register MCP servers and wire external modules."

  _ok "svelte project initialization complete"
}

main "$@"
