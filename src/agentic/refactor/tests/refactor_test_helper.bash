#!/usr/bin/env bats
# Shared setup() and helpers for the refactor test files (loaded via `load`).

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/refactor.sh"
  FIXTURE_LANGS="${TEST_DIR}/fixtures/langs"
  EDGE_LANGS="${TEST_DIR}/fixtures/langs-edge"
  PHP_PLUGIN="${MODULE_DIR}/langs/php/plugin.sh"
  PHP_FIXTURES="${TEST_DIR}/fixtures/php"
  TS_PLUGIN="${MODULE_DIR}/langs/ts/plugin.sh"
  TS_FIXTURES="${TEST_DIR}/fixtures/ts"
  PY_PLUGIN="${MODULE_DIR}/langs/py/plugin.sh"
  PY_FIXTURES="${TEST_DIR}/fixtures/py"
}

# True when the TypeScript plugin can run for real.
_ts_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${TS_PLUGIN}" doctor --project "${TS_FIXTURES}/rename-demo" >/dev/null 2>&1
}

# True when the Python plugin can run for real.
_py_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PY_PLUGIN}" doctor --project "${PY_FIXTURES}/rename-demo" >/dev/null 2>&1
}

# Build a request JSON via python — avoids nested shell-quoting entirely.
_req() {
  python3 - "$@" <<'PY'
import json, sys
args = (sys.argv[1:] + ["", "", "", ""])[:4]
op, klass, old, new = args
print(json.dumps({"op": op, "class": klass or None, "from": old, "to": new,
                  "apply": False, "scope": ["/app/src"]}))
PY
}

# True when a real end-to-end run is possible.
_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/bare" 2>/dev/null |
    grep -q '"via": "scratch"'
}

# A throwaway git repo, optionally dirtied, for the working-tree guard.
_make_repo() {
  local repo="$1" dirty="$2"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email t@example.com
  git -C "${repo}" config user.name tester
  printf 'clean\n' > "${repo}/a.txt"
  git -C "${repo}" add a.txt
  git -C "${repo}" commit -qm init
  [[ "${dirty}" == "dirty" ]] && printf 'dirty\n' >> "${repo}/a.txt"
  return 0
}

