#!/usr/bin/env bash
# Test fixture: a source adapter that reports partial errors.
set -euo pipefail

case "${1:-}" in
  meta) printf '{"source":"errors","capabilities":["pull-requests"]}\n' ;;
  doctor) printf '{"ok":true,"source":"errors"}\n' ;;
  fetch) printf '{"ok":true,"pull_requests":[],"errors":["partial: some pages failed"]}\n' ;;
  *)
    echo "ERROR: unknown verb '${1:-}'" >&2
    exit 2
    ;;
esac
