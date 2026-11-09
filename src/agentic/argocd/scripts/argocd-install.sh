#!/usr/bin/env bash
# Install or verify the argocd CLI binary (arch-aware, checksummed, no profile edits).
set -euo pipefail

VERSION=""
BIN_DIR="${ARGOCD_BIN_DIR:-$HOME/.local/bin}"
FORCE=0
ADD_TO_PATH=0
JSON=0

log()  { printf '%s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
usage_die() { printf 'FATAL: %s\n' "$*" >&2; printf 'Run with --help for usage.\n' >&2; exit 2; }

usage() {
  cat <<'EOF'
Install or verify the argocd CLI binary.

  argocd-install.sh [options]

  --version <tag>     release tag, e.g. v3.6.1 (default: latest stable)
  --bin-dir <dir>     install directory (default: $ARGOCD_BIN_DIR or ~/.local/bin)
  --force             reinstall even when that version is already present
  --add-to-path       append the bin dir to ~/.bashrc when missing (off by default)
  --json              machine-readable result on stdout
  -h, --help          this help

Exit codes: 0 ok, 1 failure, 2 usage.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   [[ -n "${2:-}" ]] || usage_die "--version needs a value"; VERSION="$2"; shift 2 ;;
    --bin-dir)   [[ -n "${2:-}" ]] || usage_die "--bin-dir needs a value"; BIN_DIR="$2"; shift 2 ;;
    --force)     FORCE=1; shift ;;
    --add-to-path) ADD_TO_PATH=1; shift ;;
    --json)      JSON=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage_die "unknown option: $1" ;;
  esac
done

for bin in curl uname install; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found"
done
if [[ "$JSON" -eq 1 ]]; then
  command -v jq >/dev/null 2>&1 || die "jq is required for --json"
fi

case "$BIN_DIR" in
  \~)   BIN_DIR="$HOME" ;;
  \~/*) BIN_DIR="$HOME/${BIN_DIR:2}" ;;
esac
if [[ ! "$BIN_DIR" =~ ^[A-Za-z0-9._/~+-]+$ ]]; then
  usage_die "--bin-dir contains characters that are unsafe when written to ~/.bashrc"
fi

case "$(uname -s)" in
  Linux)  OS=linux ;;
  Darwin) OS=darwin ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac
ASSET="argocd-${OS}-${ARCH}"

if [[ -z "$VERSION" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [[ -n "$VERSION" && "$VERSION" != "null" ]] || die "cannot resolve the latest release"
fi
[[ "$VERSION" == v* ]] || VERSION="v$VERSION"

installed_version() {
  local out
  out=$("$BIN_DIR/argocd" version --client --short 2>/dev/null || true)
  printf '%s' "$out" | awk '{print $2}' | cut -d+ -f1
}

if [[ -x "$BIN_DIR/argocd" ]]; then
  CURRENT=$(installed_version)
  if [[ "$CURRENT" == "$VERSION" && "$FORCE" -eq 0 ]]; then
    log "argocd $VERSION already installed at $BIN_DIR/argocd"
    if [[ "$JSON" -eq 1 ]]; then
      jq -n --arg v "$VERSION" --arg p "$BIN_DIR/argocd" \
        '{status:"present",version:$v,path:$p}'
    fi
    exit 0
  fi
fi

mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
TMP=$(mktemp -d) || die "cannot create a temp dir"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/argoproj/argo-cd/releases/download/${VERSION}/${ASSET}"
log "downloading argocd $VERSION ($OS/$ARCH)"
curl -fsSL -o "$TMP/argocd" "$URL" || die "download failed: $URL"

curl -fsSL -o "$TMP/checksums.txt" \
  "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/cli_checksums.txt" \
  || die "cannot download checksums"

expected=$(awk -v a="$ASSET" '$2 == a {print $1}' "$TMP/checksums.txt")
[[ -n "$expected" ]] || die "no checksum for $ASSET in cli_checksums.txt"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$TMP/argocd" | awk '{print $1}')
else
  actual=$(shasum -a 256 "$TMP/argocd" | awk '{print $1}')
fi
[[ "$actual" == "$expected" ]] || die "checksum mismatch for $ASSET"

install -m 0755 "$TMP/argocd" "$BIN_DIR/argocd" || die "cannot install to $BIN_DIR"

if [[ "$ADD_TO_PATH" -eq 1 && ":$PATH:" != *":$BIN_DIR:"* ]]; then
  if ! grep -qF "export PATH=\"$BIN_DIR:\$PATH\"" "$HOME/.bashrc" 2>/dev/null; then
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR" >> "$HOME/.bashrc"
    log "added $BIN_DIR to PATH in ~/.bashrc (open a new shell)"
  fi
fi

log "installed argocd $VERSION at $BIN_DIR/argocd"
if [[ "$JSON" -eq 1 ]]; then
  jq -n --arg v "$VERSION" --arg p "$BIN_DIR/argocd" \
    '{status:"installed",version:$v,path:$p}'
fi
