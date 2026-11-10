#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154  # fixtures set/read by the suites that load this helper
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
#
# The origin repos are identical for every caller of the same shape, so they
# are seeded once per test file into BATS_FILE_TMPDIR and copied per test. The
# suites are git-write heavy (each test used to re-init and re-commit), which is
# what they contend on when bats runs files in parallel.
# =============================================================================

# Git identity for the sandbox commits — never the developer's global config.
_update_git_identity() {
  export GIT_AUTHOR_NAME="update-tests"
  export GIT_AUTHOR_EMAIL="update-tests@example.com"
  export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
  export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
}

# Once per test file (`setup_file`): the cache locations.
_update_file_setup() {
  # Exported on purpose: bats runs every test in its own process, so only
  # exported values cross from setup_file into the tests.
  export UPDATE_ORIGIN_CACHE="${BATS_FILE_TMPDIR}/origin-cache"
  export UPDATE_SHALLOW_ORIGIN_CACHE="${BATS_FILE_TMPDIR}/shallow-origin-cache"
}

# Common per-test setup: bats libs, repo paths, and the git identity. The
# identity is set here rather than only in setup_file so a suite that forgets
# setup_file still commits as the sandbox identity (and just skips the cache)
# instead of committing as the developer.
_update_setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  UPDATE_SH="${REPO_ROOT}/bin/update.sh"

  _update_git_identity
}

_update_teardown() {
  if [[ -n "${SANDBOX:-}" && -d "${SANDBOX}" ]]; then
    rm -rf "${SANDBOX}"
  fi
}

# ── Cached origins ───────────────────────────────────────────────────────────

# Seed a repo at $1 with main carrying $2... as tags, each committing "v<N>"
# into f.txt.
_seed_origin_with_tags() {
  local dir="$1"
  shift
  git init -q "${dir}"
  git -C "${dir}" symbolic-ref HEAD refs/heads/main
  local v
  for v in "$@"; do
    printf 'v%s\n' "${v}" > "${dir}/f.txt"
    git -C "${dir}" add f.txt
    git -C "${dir}" commit -qm "commit for ${v}"
    git -C "${dir}" tag "${v}"
  done
}

_seed_origin_cache() {
  _seed_origin_with_tags "$1" 1.0.0 1.1.0
}

_seed_shallow_origin_cache() {
  _seed_origin_with_tags "$1" 1.0.0 1.1.0
  printf 'dev\n' > "$1/dev.txt"
  git -C "$1" add dev.txt
  git -C "$1" commit -qm "dev after 1.1.0"
}

# Seed a cache on first use, so a suite that never needs the shallow origin does
# not pay for it. The seed is published with an atomic rename: under within-file
# parallelism two tests can reach here at once (setup_file and BATS_FILE_TMPDIR
# are per file, not per test), and a half-seeded directory would break the
# `git clone` that follows.
_publish_cache() {
  local cache="$1" seeder="$2"
  [[ -d "${cache}" ]] && return 0

  local staging="${cache}.$$"
  "${seeder}" "${staging}"
  # First writer wins; the rest discard their staging copy.
  mv "${staging}" "${cache}" 2>/dev/null || rm -rf "${staging}"

  [[ -d "${cache}" ]] || {
    echo "ERROR: could not seed the fixture cache at ${cache}" >&2
    return 1
  }
}

_ensure_origin_cache() {
  _publish_cache "${UPDATE_ORIGIN_CACHE}" _seed_origin_cache
}

_ensure_shallow_origin_cache() {
  _publish_cache "${UPDATE_SHALLOW_ORIGIN_CACHE}" _seed_shallow_origin_cache
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
  export HARNESS_STUB_MARKER="${SANDBOX}/harness-stub-ran"

  # "" (as opposed to no argument) means the origin carries no tags at all.
  local versions="${1-1.0.0:1.1.0}"

  if [[ "${versions}" == "1.0.0:1.1.0" && -n "${UPDATE_ORIGIN_CACHE:-}" ]]; then
    _ensure_origin_cache
    cp -R "${UPDATE_ORIGIN_CACHE}" "${ORIGIN}"
  else
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
    "${REPO_ROOT}/src/_shared/migrate_workflow_config.py" \
    "${REPO_ROOT}/src/_shared/migrate_workspace_config.py" \
    "${INSTALL}/src/_shared/"

  # external-modules update stub — records that devbot update refreshed the
  # external module repos. That happens through the module update loop
  # (src/tools/*/update.sh; the real update.sh is a symlink to install.sh), not
  # through a separate pass, so the stub sits where the loop looks.
  cat > "${INSTALL}/src/tools/external-modules/update.sh" <<'STUB'
#!/usr/bin/env bash
# Test stub: record that devbot update ran the external-modules refresh.
touch "${MODULE_STUB_MARKER:-/tmp/module-stub-ran}"
STUB
  chmod +x "${INSTALL}/src/tools/external-modules/update.sh"

  # Harness stub — records that the harnesses update loop ran.
  mkdir -p "${INSTALL}/src/harnesses/opencode"
  cat > "${INSTALL}/src/harnesses/opencode/update.sh" <<'STUB'
#!/usr/bin/env bash
# Test stub: record that devbot update ran the harnesses loop.
touch "${HARNESS_STUB_MARKER:-/tmp/harness-stub-ran}"
STUB
  chmod +x "${INSTALL}/src/harnesses/opencode/update.sh"
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
  export HARNESS_STUB_MARKER="${SANDBOX}/harness-stub-ran"

  if [[ -n "${UPDATE_SHALLOW_ORIGIN_CACHE:-}" ]]; then
    _ensure_shallow_origin_cache
    cp -R "${UPDATE_SHALLOW_ORIGIN_CACHE}" "${ORIGIN}"
  else
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
  fi

  git clone -q --depth 1 --branch "${ref}" "${ORIGIN}" "${INSTALL}"
  _install_machinery
}

# Publish a newer release in origin: advance main with a commit touching
# $1=<file> with content $2, tag it $3. When $4 is given the tag is annotated
# carrying that message — the shape tag.sh produces from a release file;
# without it the tag stays lightweight, as the older fixtures are.
_publish_release() {
  local file="$1" content="$2" version="$3" notes="${4:-}"
  git -C "${ORIGIN}" checkout -q main
  printf '%s\n' "${content}" > "${ORIGIN}/${file}"
  git -C "${ORIGIN}" add "${file}"
  git -C "${ORIGIN}" commit -qm "release ${version}"
  if [[ -n "${notes}" ]]; then
    # -F + --cleanup=whitespace mirrors tag.sh: -m defaults to `strip`, which
    # would delete the release file's "# Release vX" heading as a comment.
    printf '%s' "${notes}" > "${ORIGIN}/.release-notes"
    git -C "${ORIGIN}" tag -a "${version}" --cleanup=whitespace -F "${ORIGIN}/.release-notes"
    rm -f "${ORIGIN}/.release-notes"
  else
    git -C "${ORIGIN}" tag "${version}"
  fi
}

# Point the fake install at $1 (a tag), fetching first so tags published after
# the clone are available.
_checkout_install_tag() {
  git -C "${INSTALL}" fetch -q --tags origin
  git -C "${INSTALL}" checkout -q --detach "$1"
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
