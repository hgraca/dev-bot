#!/usr/bin/env bash
# Test fixture: a working units-capable plugin for the `.zz` extension.
set -euo pipefail

case "${1:-}" in
  meta) echo '{"lang":"gt","extensions":[".zz"],"capabilities":["units"]}' ;;
  units)
    cat >/dev/null
    echo '{"ok":true,"units":[{"path":"a.zz","name":"a","kind":"function","start_line":1,"end_line":1,"complexity":1,"loc":1,"parent":""}]}'
    ;;
  *) exit 1 ;;
esac
