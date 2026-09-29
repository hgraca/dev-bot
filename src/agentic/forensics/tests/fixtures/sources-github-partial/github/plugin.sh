#!/usr/bin/env bash
# Test fixture: a `github` adapter whose fetch succeeds but reports partial errors.
set -euo pipefail

case "${1:-}" in
  meta) printf '{"source":"github","capabilities":["pull-requests"]}\n' ;;
  doctor) printf '{"ok":true,"source":"github"}\n' ;;
  fetch) printf '{"ok":true,"pull_requests":[],"errors":["partial: some pages failed"]}\n' ;;
  *)
    echo "ERROR: unknown verb '${1:-}'" >&2
    exit 2
    ;;
esac
