#!/usr/bin/env bash
# src/agentic/k8s/install.sh
# Installs kubeconform and kube-linter from GitHub releases to ~/.local/bin.
# Idempotent — skips tools already present.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

INSTALL_DIR="${HOME}/.local/bin"

_ensure_install_dir() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        _ok "Created $INSTALL_DIR"
    fi
}

_detect_platform() {
    local os arch
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="darwin" ;;
        *)
            _fatal "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            _fatal "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    echo "${os}-${arch}"
}

# Fetch latest release tag from GitHub API. Args: owner repo
_fetch_latest_tag() {
    local owner="$1" repo="$2"
    curl -sSL "https://api.github.com/repos/${owner}/${repo}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

install_kubeconform() {
    _info "kubeconform"

    if command -v kubeconform >/dev/null 2>&1; then
        _skip "kubeconform already installed ($(kubeconform -v 2>&1 | head -1))"
        return 0
    fi

    local platform tag url tmpdir
    platform="$(_detect_platform)"
    _info "Detected platform: $platform"

    _info "Fetching latest kubeconform release..."
    tag="$(_fetch_latest_tag "yannh" "kubeconform")"
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        _error "Failed to fetch latest kubeconform release tag"
        return 1
    fi
    _info "Latest: $tag (stripping 'v' prefix for download URL)"

    local os arch
    os="${platform%-*}"
    arch="${platform#*-}"
    local clean_tag="${tag#v}"
    url="https://github.com/yannh/kubeconform/releases/download/${tag}/kubeconform-${os}-${arch}.tar.gz"

    _info "Downloading $url ..."
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")"
    curl -sSL "$url" -o "$tmpdir/kubeconform.tar.gz" || {
        _error "Download failed"
        rm -rf "$tmpdir"
        return 1
    }

    tar xzf "$tmpdir/kubeconform.tar.gz" -C "$tmpdir"
    cp "$tmpdir/kubeconform" "$INSTALL_DIR/kubeconform"
    chmod +x "$INSTALL_DIR/kubeconform"
    rm -rf "$tmpdir"

    _ok "kubeconform $clean_tag installed to $INSTALL_DIR/kubeconform"
}

install_kubelinter() {
    _info "kube-linter"

    if command -v kube-linter >/dev/null 2>&1; then
        _skip "kube-linter already installed ($(kube-linter version 2>&1 | head -1))"
        return 0
    fi

    local platform tag url tmpdir
    platform="$(_detect_platform)"
    _info "Detected platform: $platform"

    _info "Fetching latest kube-linter release..."
    tag="$(_fetch_latest_tag "stackrox" "kube-linter")"
    if [[ -z "$tag" || "$tag" == "null" ]]; then
        _error "Failed to fetch latest kube-linter release tag"
        return 1
    fi
    _info "Latest: $tag"

    local api_json url
    api_json="$(curl -sSL "https://api.github.com/repos/stackrox/kube-linter/releases/tags/${tag}")"

    # Find the archive URL for this platform.
    # kube-linter archive pattern: kube-linter-linux.tar.gz (no arch in name)
    local os="${platform%-*}"
    url="$(echo "$api_json" | grep "browser_download_url" | grep "${os}\.tar\.gz" | grep -v "sha256" | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')"

    if [[ -z "$url" ]]; then
        _error "No kube-linter binary found for platform $platform"
        return 1
    fi

    _info "Downloading $url ..."
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")"
    curl -sSL "$url" -o "$tmpdir/kube-linter.tar.gz" || {
        _error "Download failed"
        rm -rf "$tmpdir"
        return 1
    }

    tar xzf "$tmpdir/kube-linter.tar.gz" -C "$tmpdir"
    cp "$tmpdir/kube-linter" "$INSTALL_DIR/kube-linter"
    chmod +x "$INSTALL_DIR/kube-linter"
    rm -rf "$tmpdir"

    _ok "kube-linter ${tag#v} installed to $INSTALL_DIR/kube-linter"
}

main() {
    _header_1 "k8s module install"
    _ensure_install_dir
    install_kubeconform
    install_kubelinter
    _header_1 "k8s install complete"
}

main
