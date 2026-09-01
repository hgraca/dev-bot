#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/prereq_tests.bats
# Tests for _check_python3() in src/_shared/functions.sh.
#
# audit-25 F1/F3: macOS ships /usr/bin/python3 = 3.9.6, older than the 3.10
# floor the Python tools assume. _check_python3 must detect an old python,
# attempt a Homebrew install/upgrade on Darwin, and never silently pass.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  source "$PROJECT_ROOT/src/_shared/functions.sh"

  MOCK="$(mktemp -d)"
}

teardown() {
  rm -rf "$MOCK"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# A fake python3 reporting a given version (e.g. "3.9.6").
_mock_python3() {
  cat > "$MOCK/python3" <<SCRIPT
#!/bin/bash
if [[ "\$1" == "--version" ]]; then
  echo "Python $1"
  exit 0
fi
exit 0
SCRIPT
  chmod +x "$MOCK/python3"
}

# A fake uname reporting the given system name (e.g. "Darwin").
_mock_uname() {
  cat > "$MOCK/uname" <<SCRIPT
#!/bin/bash
echo "$1"
SCRIPT
  chmod +x "$MOCK/uname"
}

# A fake brew that records its invocation to a marker file and exits 0.
_mock_brew() {
  cat > "$MOCK/brew" <<SCRIPT
#!/bin/bash
echo "\$*" >> "$MOCK/brew-calls.log"
exit 0
SCRIPT
  chmod +x "$MOCK/brew"
}

# ── Existence / modern version ────────────────────────────────────────────────

@test "python3 modern (>= 3.10): reports ok" {
  command -v python3 &>/dev/null || skip "python3 not installed"
  # The real host python3 is assumed >= 3.10 in CI/dev environments.
  local ver
  ver="$(python3 --version 2>&1 | sed -n 's/^Python \([0-9]*\.[0-9]*\).*/\1/p')"
  local major="${ver%%.*}"
  local minor="${ver##*.}"
  if [[ "${major}" -lt 3 || ( "${major}" -eq 3 && "${minor}" -lt 10 ) ]]; then
    skip "host python3 is ${ver} (< 3.10) — cannot assert the ok path"
  fi

  run _check_python3
  assert_success
  assert_output --partial "python3 found"
  refute_output --partial "WARN"
}

@test "python3 missing: fatal on non-Darwin (no brew fallback)" {
  _mock_uname "Linux"
  # Filter every PATH dir that contains a python3 binary.
  local filtered_path dir
  filtered_path=""
  while IFS= read -r -d: dir; do
    [[ -n "$dir" && ! -x "$dir/python3" ]] || continue
    filtered_path="${filtered_path:+$filtered_path:}$dir"
  done <<< "${PATH}:"
  [[ -n "$filtered_path" ]] || skip "cannot build a python3-free PATH"

  PATH="$MOCK:$filtered_path" run _check_python3
  assert_failure
  assert_output --partial "FATAL"
  assert_output --partial "python3 is required"
}

# ── Old version (3.9) — the audit-25 macOS scenario ──────────────────────────

@test "python3 3.9 on Linux: warns, does not fail" {
  _mock_python3 "3.9.6"
  _mock_uname "Linux"

  PATH="$MOCK:/usr/bin:/bin" run _check_python3
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "3.9"
}

@test "python3 3.9 on Darwin with brew: brew upgrade attempted, then warns" {
  _mock_python3 "3.9.6"
  _mock_uname "Darwin"
  _mock_brew

  PATH="$MOCK:/usr/bin:/bin" run _check_python3
  assert_success
  assert_output --partial "WARN"
  # brew was invoked with an install/upgrade of python
  run cat "$MOCK/brew-calls.log"
  assert_success
  assert_output --partial "python"
}

@test "python3 3.9 on Darwin without brew: warns, no crash" {
  _mock_python3 "3.9.6"
  _mock_uname "Darwin"

  PATH="$MOCK:/usr/bin:/bin" run _check_python3
  assert_success
  assert_output --partial "WARN"
}

# A flock-free PATH (filter every dir that contains a flock binary), with
# $MOCK prepended. Used to simulate a macOS host that lacks util-linux.
_flock_free_path() {
  local filtered_path dir
  filtered_path=""
  while IFS= read -r -d: dir; do
    [[ -n "$dir" && ! -x "$dir/flock" ]] || continue
    filtered_path="${filtered_path:+$filtered_path:}$dir"
  done <<< "${PATH}:"
  echo "$MOCK:${filtered_path}"
}

# ── _check_flock (audit-25 F2: flock(1) is util-linux, absent on macOS) ───────

@test "flock present: reports ok, no brew invocation" {
  command -v flock &>/dev/null || skip "flock not installed"
  _mock_uname "Linux"

  run _check_flock
  assert_success
  assert_output --partial "flock found"
  refute_output --partial "WARN"
}

@test "flock missing on Darwin with brew: installs util-linux and adds keg-only bin to PATH" {
  _mock_uname "Darwin"
  # Simulate a successful brew install under a mock HOMEBREW_PREFIX: the brew
  # stub creates the keg-only flock binary (util-linux is keg-only — not
  # symlinked onto PATH by brew). The stub runs under a flock-free PATH that
  # excludes /usr/bin (which contains flock on Linux), so external commands
  # are baked in as absolute paths.
  local mkdir_bin chmod_bin
  mkdir_bin="$(command -v mkdir)"
  chmod_bin="$(command -v chmod)"
  mkdir -p "$MOCK/opt/util-linux/bin"
  cat > "$MOCK/brew" <<SCRIPT
#!/bin/bash
echo "\$*" >> "$MOCK/brew-calls.log"
"$mkdir_bin" -p "$MOCK/opt/util-linux/bin"
printf '#!/bin/bash\nexit 0\n' > "$MOCK/opt/util-linux/bin/flock"
"$chmod_bin" +x "$MOCK/opt/util-linux/bin/flock"
exit 0
SCRIPT
  chmod +x "$MOCK/brew"

  # PATH without flock; _check_flock must locate the keg-only bin itself.
  local flock_free
  flock_free="$(_flock_free_path)"
  [[ "$flock_free" != "$MOCK:" ]] || skip "cannot build a flock-free PATH"
  export HOMEBREW_PREFIX="$MOCK"
  PATH="$flock_free" run _check_flock
  assert_success
  assert_output --partial "flock found"
  run cat "$MOCK/brew-calls.log"
  assert_output --partial "util-linux"
}

@test "flock missing on Darwin without brew: warns, does not fail" {
  _mock_uname "Darwin"

  local flock_free
  flock_free="$(_flock_free_path)"
  [[ "$flock_free" != "$MOCK:" ]] || skip "cannot build a flock-free PATH"
  PATH="$flock_free" run _check_flock
  assert_success
  assert_output --partial "WARN"
}

@test "flock missing on Linux: warns, does not fail" {
  _mock_uname "Linux"

  local flock_free
  flock_free="$(_flock_free_path)"
  [[ "$flock_free" != "$MOCK:" ]] || skip "cannot build a flock-free PATH"

  PATH="$flock_free" run _check_flock
  assert_success
  assert_output --partial "WARN"
}
