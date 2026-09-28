#!/usr/bin/env bash
# Test fixture: a source adapter that returns an empty, quiet window.
set -euo pipefail

case "${1:-}" in
  meta) printf '{"source":"empty","capabilities":["pull-requests"]}\n' ;;
  doctor) printf '{"ok":true,"source":"empty"}\n' ;;
  fetch) printf '{"ok":true,"pull_requests":[],"errors":[]}\n' ;;
  *)
    echo "ERROR: unknown verb '${1:-}'" >&2
    exit 2
    ;;
esac
