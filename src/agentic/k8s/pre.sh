#!/usr/bin/env bash
# src/agentic/k8s/pre.sh
# Checks prerequisites for kubeconform and kube-linter module.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

_header_1 "k8s prerequisites"

# Required: curl for downloading release binaries
if ! command -v curl &>/dev/null; then
    _error "curl is required to download kubeconform and kube-linter binaries"
    exit 1
fi
_ok "curl found"

# Required: tar for extracting release archives
if ! command -v tar &>/dev/null; then
    _error "tar is required to extract release archives"
    exit 1
fi
_ok "tar found"

# Optional: network check (warn only — user may be offline, already installed)
if curl --connect-timeout 5 --head https://github.com >/dev/null 2>&1; then
    _ok "GitHub reachable"
else
    _warn "GitHub not reachable — install.sh may fail if binaries need download"
fi

_header_1 "k8s prerequisites OK"
