#!/usr/bin/env bash
# Test fixture: a units-capable plugin whose `units` always fails.
set -euo pipefail

case "${1:-}" in
  meta) echo '{"lang":"bad","extensions":[".zz"],"capabilities":["units"]}' ;;
  units)
    echo "ERROR: boom" >&2
    exit 1
    ;;
  *) exit 1 ;;
esac
