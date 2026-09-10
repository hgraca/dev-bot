#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_tests.bats
# Tests for bin/update.sh — the tag-based release updater.
#
# devbot update is release-tracked: it fetches tags from origin and only
# touches the checkout when a NEWER tag exists than the current position.
#   - at/ahead of the newest tag  -> "already on latest" + exit 0 (no refresh)
#   - strictly behind the tag     -> stash dirty tree, detach-jump to the tag,
#                                    stash pop (conflict => ack prompt, continue)
#   - diverged branch             -> rebase the branch onto the tag; on failure
#                                    abort the rebase, restore state, exit 1
#   - after a successful jump     -> npm + tools + agentic + external modules
#                                    (module.sh install) refresh; harnesses never
#                                    touched, and the release tag is recorded in
#                                    the global config `version` (the per-project
#                                    reinit trigger). No reinit runs here.
#   - --auto                      -> quiet no-op when already newest; never
#                                    prompts. Used by the bare-`devbot` start.
#
# The fake "installation" is a sandbox git clone whose origin is a second
# sandbox repo. bin/update.sh + src/_shared are copied in (DEV_BOT_ROOT is
# derived from the script location), there is no package.json (npm step
# naturally skips), module dirs are empty (0 update.sh scripts), and
# module.sh is a stub that records invocation via a marker file.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  UPDATE_SH="${REPO_ROOT}/bin/update.sh"

  # Git identity for all sandbox commits (no reliance on user config).
  export GIT_AUTHOR_NAME="update-tests"
  export GIT_AUTHOR_EMAIL="update-tests@example.com"
  export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
  export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
}

teardown() {
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
  mkdir -p "${INSTALL}/bin" \
    "${INSTALL}/src/_shared" \
    "${INSTALL}/src/tools/external-modules/tools" \
    "${INSTALL}/src/tools" \
    "${INSTALL}/src/agentic"
  cp "${UPDATE_SH}" "${INSTALL}/bin/update.sh"
  cp "${REPO_ROOT}/src/_shared/functions.sh" \
    "${REPO_ROOT}/src/_shared/read_jsonc.py" \
    "${INSTALL}/src/_shared/"

  # module.sh stub — records invocation, never touches the network.
  cat > "${INSTALL}/src/tools/external-modules/tools/module.sh" <<'STUB'
#!/usr/bin/env bash
# Test stub: record that devbot update invoked the external-modules refresh.
touch "${MODULE_STUB_MARKER:-/tmp/module-stub-ran}"
STUB
  chmod +x "${INSTALL}/src/tools/external-modules/tools/module.sh"
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

# ── No-newer-release paths (echo + exit, nothing else) ───────────────────────

@test "already at the newest tag: says latest and exits 0 with no refresh" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  ! _refresh_ran
}

@test "ahead of the newest tag (dev on main): says latest and exits 0" {
  _new_sandbox "1.0.0:1.1.0"
  # Local commit beyond the newest tag — newest tag is an ancestor of HEAD.
  git -C "${INSTALL}" checkout -q main
  printf 'local work\n' > "${INSTALL}/dev.txt"
  git -C "${INSTALL}" add dev.txt
  git -C "${INSTALL}" commit -qm "local commit after latest release"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  ! _refresh_ran
}

@test "no tags at all: reports nothing to update and exits 0" {
  _new_sandbox ""
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"release tags"* ]]
  ! _refresh_ran
}

@test "fetch failure: exits 1 with an error" {
  _new_sandbox "1.0.0:1.1.0"
  git -C "${INSTALL}" remote set-url origin "${SANDBOX}/does-not-exist"
  _run_update

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"fetch"* ]]
  ! _refresh_ran
}

@test "fetch timeout: a stalled fetch is killed and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  # Fake git: hang on `fetch`, delegate every other subcommand to the real git.
  local real_git
  real_git="$(command -v git)"
  mkdir -p "${SANDBOX}/mockbin"
  cat > "${SANDBOX}/mockbin/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "fetch" ]]; then sleep 30; exit 0; fi
done
exec "${real_git}" "\$@"
EOF
  chmod +x "${SANDBOX}/mockbin/git"

  # PATH scoped to this invocation only — never leak the mock into other tests.
  PATH="${SANDBOX}/mockbin:${PATH}" DEV_BOT_FETCH_TIMEOUT=1 _run_update

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"within 1s"* ]]
  ! _refresh_ran
}

# ── Path A: strictly behind -> detach-jump ───────────────────────────────────

@test "behind: detaches onto the newest tag and runs the refresh block" {
  _new_sandbox "1.0.0:1.1.0"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  _refresh_ran
  [[ "$UPDATE_OUTPUT" == *"1.2.0"* ]]
  # The post-jump refresh runs _devbot_detect_gpu (bin/update.sh). The sandbox
  # install has no .devbot.global.jsonc, so the helper hits its first guard —
  # asserting that message proves the GPU-detection call site is reached
  # (without depending on the host's GPU state).
  [[ "$UPDATE_OUTPUT" == *"gpu detection skipped"* ]]
}

@test "behind with dirty tree: stashes, jumps, reapplies cleanly" {
  _new_sandbox "1.0.0:1.1.0"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"
  # Local unstaged edit to a file untouched by the new release.
  printf 'local tweak\n' >> "${INSTALL}/f.txt"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  _refresh_ran
  # Stash popped cleanly: edit restored, no stash left behind.
  grep -q 'local tweak' "${INSTALL}/f.txt"
  run git -C "${INSTALL}" stash list
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "behind with conflicting stash pop: warns and continues past it" {
  _new_sandbox "1.0.0:1.1.0"
  # New release touches f.txt (the same file the local edit touches) -> pop
  # will conflict. Feed a keypress on stdin for the ack.
  _publish_release "f.txt" "release 1.2.0" "1.2.0"
  printf 'local tweak\n' >> "${INSTALL}/f.txt"

  run bash -c "printf 'x\n' | bash '${INSTALL}/bin/update.sh'"
  UPDATE_STATUS="$status"
  UPDATE_OUTPUT="$output"

  [ "$UPDATE_STATUS" -eq 0 ]
  _refresh_ran
  # The conflict warning is shown (the ack wait itself is not observable on a
  # non-tty stdin, but the warn-and-continue contract is).
  [[ "$UPDATE_OUTPUT" == *"conflict"* ]]
  # Conflict left in the working tree for the user to fix later.
  run git -C "${INSTALL}" status --porcelain --untracked-files=no
  [[ "$output" == *"UU f.txt"* || "$output" == *"AA f.txt"* || "$output" == *"U"* ]]
}

# ── Path B: diverged branch -> rebase onto the tag ───────────────────────────

@test "diverged branch: rebases onto the newest tag, keeps branch and work" {
  _new_sandbox "1.0.0:1.1.0"
  # Feature branch with its own commit (new file — no overlap with releases).
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature work\n' > "${INSTALL}/feature.txt"
  git -C "${INSTALL}" add feature.txt
  git -C "${INSTALL}" commit -qm "feature commit"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  # Still on the feature branch (not detached), work preserved, tag now base.
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  grep -q 'feature work' "${INSTALL}/feature.txt"
  git -C "${INSTALL}" merge-base --is-ancestor 1.2.0 HEAD
  _refresh_ran
}

@test "diverged branch, rebase conflict: aborts, restores state, exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  # Feature commit edits f.txt; the new release also edits f.txt -> rebase
  # conflict. Capture the branch position before the run.
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature edit\n' > "${INSTALL}/f.txt"
  git -C "${INSTALL}" add f.txt
  git -C "${INSTALL}" commit -qm "feature edit"
  _publish_release "f.txt" "release 1.2.0" "1.2.0"
  local pre_sha
  pre_sha="$(git -C "${INSTALL}" rev-parse HEAD)"

  _run_update

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"rebase"* ]]
  # State restored: branch ref back at the pre-attempt commit, clean tracked
  # tree (untracked machinery dirs are fixture artifacts, never touched).
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "${pre_sha}"
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  run git -C "${INSTALL}" status --porcelain --untracked-files=no
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  run git -C "${INSTALL}" stash list
  [[ -z "$output" ]]
  ! _refresh_ran
}

# ── Explicit target: devbot update <tag> ─────────────────────────────────────

@test "explicit older tag from a newer position: downgrades (detach) + refresh" {
  _new_sandbox "1.0.0:1.1.0" # install detached at 1.1.0 (newest)
  _run_update 1.0.0

  [ "$UPDATE_STATUS" -eq 0 ]
  # Detached HEAD now sitting exactly on the requested tag's commit.
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "$(git -C "${INSTALL}" rev-parse '1.0.0^{commit}')"
  run git -C "${INSTALL}" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  _refresh_ran
  [[ "$UPDATE_OUTPUT" == *"1.0.0"* ]]
}

@test "explicit target already checked out: says already on and exits 0" {
  _new_sandbox "1.0.0:1.1.0" # install detached at 1.1.0
  _run_update 1.1.0

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on 1.1.0"* ]]
  ! _refresh_ran
}

@test "explicit nonexistent tag: errors, lists tags, exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 9.9.9

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"does not exist"* ]]
  [[ "$UPDATE_OUTPUT" == *"9.9.9"* ]]
  [[ "$UPDATE_OUTPUT" == *"1.1.0"* ]] # available-tags listing shown
  ! _refresh_ran
}

@test "explicit tag on a diverged branch: rebases onto the requested tag" {
  _new_sandbox "1.0.0:1.1.0"
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature work\n' > "${INSTALL}/feature.txt"
  git -C "${INSTALL}" add feature.txt
  git -C "${INSTALL}" commit -qm "feature commit"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update 1.2.0

  [ "$UPDATE_STATUS" -eq 0 ]
  # Still on the feature branch (not detached), work preserved, tag now base.
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  grep -q 'feature work' "${INSTALL}/feature.txt"
  git -C "${INSTALL}" merge-base --is-ancestor 1.2.0 HEAD
  _refresh_ran
}

# ── Version recording (the per-project reinit trigger) ───────────────────────

@test "behind: records the release tag in the global config version" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" version)" \
    "1.2.0"
}

@test "a real update does not run reinit (the version bump drives it lazily)" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  # A reinit stub that would leave a marker if update invoked it.
  cat > "${INSTALL}/bin/reinit.sh" <<EOF
#!/usr/bin/env bash
touch "${SANDBOX}/reinit-ran"
EOF
  chmod +x "${INSTALL}/bin/reinit.sh"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [ ! -e "${SANDBOX}/reinit-ran" ]
}

# ── Auto mode (bare-`devbot` start) ──────────────────────────────────────────

@test "--auto at the newest tag: one-line no-op, no banner" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  [[ "$UPDATE_OUTPUT" != *"DevBot Update"* ]]
  [[ "$UPDATE_OUTPUT" != *"Fetching release tags"* ]]
  ! _refresh_ran
}

@test "--auto behind: updates and records the version" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" version)" \
    "1.2.0"
}

@test "--auto after the tag is honored (flag order independent)" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 1.1.0 --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on 1.1.0"* ]]
  # --auto was parsed: no banner, no fetch chatter.
  [[ "$UPDATE_OUTPUT" != *"DevBot Update"* ]]
  [[ "$UPDATE_OUTPUT" != *"Fetching release tags"* ]]
}

@test "unknown option: errors and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update --bogus

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"Unknown option"* ]]
}

@test "two tags: errors and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 1.0.0 1.1.0

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"Unexpected extra argument"* ]]
}

@test "concurrent update: skips when the update lock is held" {
  _new_sandbox "1.0.0:1.1.0"
  mkdir -p "${INSTALL}/storage/run"
  # Hold the update lock for the duration (same flock fd the script uses).
  ( exec 200>"${INSTALL}/storage/run/update.lock"; flock -x 200; sleep 3 ) &
  local holder=$!
  sleep 0.3

  DEV_BOT_UPDATE_LOCK_WAIT=0 _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"another devbot update is in progress"* ]]
  ! _refresh_ran

  kill "${holder}" 2>/dev/null || true
}
