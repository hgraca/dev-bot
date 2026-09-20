#!/usr/bin/env bash
# =============================================================================
# bin/tests/update_helpers.bash
# Shared fixture builders for the bin/update.sh suites. Never run directly —
# bats only discovers *.bats; each suite picks this up with `load update_helpers`.
#
# The fake "installation" is a sandbox git clone whose origin is a second
# sandbox repo. bin/update.sh + src/_shared are copied in (DEV_BOT_ROOT is
# derived from the script location), there is no package.json (npm step
# naturally skips), module dirs are empty (0 update.sh scripts), and
# module.sh is a stub that records invocation via a marker file.
# =============================================================================

# Common per-test setup: bats libs, repo paths, and a git identity for the
# sandbox commits (no reliance on user config).
_update_setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  UPDATE_SH="${REPO_ROOT}/bin/update.sh"

  export GIT_AUTHOR_NAME="update-tests"
  export GIT_AUTHOR_EMAIL="update-tests@example.com"
  export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
  export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
}

_update_teardown() {
  if [[ -n "${SANDBOX:-}" && -d "${SANDBOX}" ]]; then
    rm -rf "${SANDBOX}"
  fi
}

# ── Fixture builders ─────────────────────────────────────────────────────────

# Create a new sandbox. $1 optional: colon-list of versions to tag on main
# (default "1.0.0:1.1.0"). Each tagged version commits "v<N>" into f.txt,
# advancing main. INSTALL is a clone sitting detached on the newest tag.
_new_sandbox() {
  SANDBOX="$(mktemp -d)"
  ORIGIN="${SANDBOX}/origin"
  INSTALL="${SANDBOX}/install"
  export MODULE_STUB_MARKER="${SANDBOX}/module-stub-ran"

  local versions="${1:-1.0.0:1.1.0}"

  git init -q "${ORIGIN}"
  git -C "${ORIGIN}" symbolic-ref HEAD refs/heads/main

  if [[ -n "${versions}" ]]; then
    IFS=':' read -r -a ver_list <<<"${versions}"
    for v in "${ver_list[@]}"; do
      printf 'v%s\n' "${v}" > "${ORIGIN}/f.txt"
      git -C "${ORIGIN}" add f.txt
      git -C "${ORIGIN}" commit -qm "commit for ${v}"
      git -C "${ORIGIN}" tag "${v}"
    done
  else
    printf 'base\n' > "${ORIGIN}/f.txt"
    git -C "${ORIGIN}" add f.txt
    git -C "${ORIGIN}" commit -qm "base commit"
  fi

  git clone -q "${ORIGIN}" "${INSTALL}"
  local newest
  newest="$(git -C "${INSTALL}" tag --sort=-v:refname | head -n1 || true)"
  if [[ -n "${newest}" ]]; then
    git -C "${INSTALL}" checkout -q --detach "${newest}"
  fi

  # Copy the update machinery + shared library into the fake install.
  _install_machinery
}

# Copy the update machinery + shared library into ${INSTALL} (a fake install).
_install_machinery() {
  mkdir -p "${INSTALL}/bin" \
    "${INSTALL}/src/_shared" \
    "${INSTALL}/src/tools/external-modules/tools" \
    "${INSTALL}/src/tools" \
    "${INSTALL}/src/agentic"
  cp "${UPDATE_SH}" "${INSTALL}/bin/update.sh"
  cp "${REPO_ROOT}/src/_shared/functions.sh" \
    "${REPO_ROOT}/src/_shared/read_jsonc.py" \
    "${REPO_ROOT}/src/_shared/reconcile_global_config.py" \
    "${INSTALL}/src/_shared/"

  # module.sh stub — records invocation, never touches the network.
  cat > "${INSTALL}/src/tools/external-modules/tools/module.sh" <<'STUB'
#!/usr/bin/env bash
# Test stub: record that devbot update invoked the external-modules refresh.
touch "${MODULE_STUB_MARKER:-/tmp/module-stub-ran}"
STUB
  chmod +x "${INSTALL}/src/tools/external-modules/tools/module.sh"
}

# Shallow-install sandbox, mirroring install.sh's `git clone --depth 1`.
# origin main carries tags 1.0.0/1.1.0 plus one untagged dev commit; INSTALL is
# a depth-1 clone at $1 (default main). The newest tag is an ancestor of HEAD
# in reality, but a shallow clone's truncated history cannot connect it.
_new_shallow_sandbox() {
  local ref="${1:-main}"
  SANDBOX="$(mktemp -d)"
  ORIGIN="${SANDBOX}/origin"
  INSTALL="${SANDBOX}/install"
  export MODULE_STUB_MARKER="${SANDBOX}/module-stub-ran"

  git init -q "${ORIGIN}"
  git -C "${ORIGIN}" symbolic-ref HEAD refs/heads/main
  local v
  for v in 1.0.0 1.1.0; do
    printf 'v%s\n' "${v}" > "${ORIGIN}/f.txt"
    git -C "${ORIGIN}" add f.txt
    git -C "${ORIGIN}" commit -qm "commit for ${v}"
    git -C "${ORIGIN}" tag "${v}"
  done
  printf 'dev\n' > "${ORIGIN}/dev.txt"
  git -C "${ORIGIN}" add dev.txt
  git -C "${ORIGIN}" commit -qm "dev after 1.1.0"

  git clone -q --depth 1 --branch "${ref}" "${ORIGIN}" "${INSTALL}"
  _install_machinery
}

# Publish a newer release in origin: advance main with a commit touching
# $1=<file> with content $2, tag it $3.
_publish_release() {
  local file="$1" content="$2" version="$3"
  git -C "${ORIGIN}" checkout -q main
  printf '%s\n' "${content}" > "${ORIGIN}/${file}"
  git -C "${ORIGIN}" add "${file}"
  git -C "${ORIGIN}" commit -qm "release ${version}"
  git -C "${ORIGIN}" tag "${version}"
}

_run_update() {
  run bash "${INSTALL}/bin/update.sh" "$@"
  UPDATE_STATUS="$status"
  UPDATE_OUTPUT="$output"
}

_newest_tag_commit() {
  local newest=""
  read -r newest < <(git -C "${INSTALL}" tag --sort=-v:refname) || true
  git -C "${INSTALL}" rev-parse "${newest}^{commit}"
}

_refresh_ran() {
  [[ -f "${MODULE_STUB_MARKER}" ]]
}

_assert_detached_at_newest_tag() {
  # Detached HEAD (no branch) sitting exactly on the newest tag commit.
  run git -C "${INSTALL}" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "$(_newest_tag_commit)"
}
