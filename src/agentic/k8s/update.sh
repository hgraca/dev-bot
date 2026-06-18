#!/usr/bin/env bash
# src/agentic/k8s/update.sh
# Updates kubeconform and kube-linter to latest versions from GitHub releases.
# Removes existing binaries then re-downloads.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
    _header_1 "k8s module update"

    # Remove existing binaries so install re-fetches latest
    local INSTALL_DIR="${HOME}/.local/bin"
    if [[ -f "$INSTALL_DIR/kubeconform" ]]; then
        _info "Removing existing kubeconform..."
        rm -f "$INSTALL_DIR/kubeconform"
    fi
    if [[ -f "$INSTALL_DIR/kube-linter" ]]; then
        _info "Removing existing kube-linter..."
        rm -f "$INSTALL_DIR/kube-linter"
    fi

    # Re-run install (will fetch latest since binaries removed)
    bash "$(dirname "$0")/install.sh"

    _header_1 "k8s update complete"
}

main
