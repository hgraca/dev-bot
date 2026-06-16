#!/usr/bin/env bash
# src/agentic/signoz/functions.sh
# Shared helpers for SigNoz module scripts (install.sh, update.sh, init.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Resolve the storage directory for SigNoz assets (binary, skills, README).
_signoz_storage_dir() {
  echo "${DEV_BOT_ROOT}/storage/signoz"
}

# Detect the archive name based on OS and architecture.
_signoz_archive_name() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${arch}" in
    x86_64)  arch="amd64"  ;;
    aarch64) arch="arm64"  ;;
  esac

  echo "signoz-mcp-server_${os}_${arch}.tar.gz"
}
