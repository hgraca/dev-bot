#!/usr/bin/env bash
# Update the managed argocd CLI to the latest release.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "argocd"

  local bin_dir="${ARGOCD_BIN_DIR:-$HOME/.local/bin}"
  local managed="${bin_dir}/argocd"
  export PATH="${bin_dir}:$PATH"

  if [[ -x "$managed" ]]; then
    _info "updating the managed argocd CLI..."
    if bash "${MODULE_DIR}/scripts/argocd-install.sh" --force --bin-dir "$bin_dir"; then
      _ok "argocd $("$managed" version --client --short 2>/dev/null || echo updated)"
    else
      _error "update failed — run scripts/argocd-install.sh --force --bin-dir $bin_dir manually"
      return 1
    fi
  elif command -v argocd >/dev/null 2>&1; then
    _warn "argocd is installed outside ${bin_dir} — installing the managed copy"
    if bash "${MODULE_DIR}/scripts/argocd-install.sh" --bin-dir "$bin_dir"; then
      _ok "argocd $("$managed" version --client --short 2>/dev/null || echo installed)"
    else
      _error "install failed — run scripts/argocd-install.sh --bin-dir $bin_dir manually"
      return 1
    fi
  else
    bash "${MODULE_DIR}/install.sh"
  fi
}

main "$@"
