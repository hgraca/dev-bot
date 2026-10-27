#!/usr/bin/env bats
# =============================================================================
# src/tools/external-modules/tests/up_tests.bats
# Tests for the external-modules up.sh — the start-time update check.
#
# Hermetic: every remote is a local bare repo inside the sandbox, so no network
# is ever touched.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  SCRIPT="${MODULE_DIR}/up.sh"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"
  python3 -c 'import fcntl' 2>/dev/null || skip "fcntl not available"

  SANDBOX="$(mktemp -d)"
  DEVROOT="${SANDBOX}/devbot"
  mkdir -p "${DEVROOT}"

  # The script reads its root from the environment (bin/up.sh exports it), so
  # the sandbox is the whole install for the duration of the test.
  export DEV_BOT_ROOT="${DEVROOT}"
  # Tests run the script more than once against one sandbox and expect each run
  # to check: force it here; the interval behaviour has its own tests below.
  export DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL=0
  # shellcheck source=../functions.sh
  source "${MODULE_DIR}/functions.sh"

  # Hermetic: "origin" is a local bare repo; the seed clone is what pushes to it.
  ORIGIN="${SANDBOX}/remotes/mod1.git"
  git init --bare -q --initial-branch=main "${ORIGIN}"

  SEED="${SANDBOX}/seed"
  git init -q --initial-branch=main "${SEED}"
  git -C "${SEED}" config user.email "test@test.com"
  git -C "${SEED}" config user.name "Test"
  # Hermetic: don't inherit the developer's global signing config.
  git -C "${SEED}" config commit.gpgsign false
  git -C "${SEED}" config tag.gpgSign false

  printf '#!/usr/bin/env bash\n' > "${SEED}/pre.sh"
  mkdir -p "${SEED}/skills" "${SEED}/agents"
  printf 'v1\n' > "${SEED}/skills/SKILL.md"
  printf 'readme\n' > "${SEED}/skills/README.md"
  printf 'agent\n' > "${SEED}/agents/AGENT.md"
  printf 'readme\n' > "${SEED}/agents/README.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "v1"
  git -C "${SEED}" remote add origin "${ORIGIN}"
  git -C "${SEED}" push -q origin main

  URL="file://${ORIGIN}"
  DEST="${DEVROOT}/vendor/$(_derive_vendor_path "${URL}")"
  STORAGE="${DEVROOT}/storage/external-agentic-modules/mod1"

  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

write_config() {
  printf '%s\n' "${1:-}" > "${DEVROOT}/.devbot.global.jsonc"
}

# Clone the module the way a real install would, so the update path is exercised
# on an existing clone rather than the install path.
preclone() {
  mkdir -p "$(dirname "${DEST}")"
  git clone -q --depth 1 "${URL}" "${DEST}"
}

# Push a new commit to the origin, changing skills/SKILL.md to the given value.
publish() {
  local value="$1"
  printf '%s\n' "${value}" > "${SEED}/skills/SKILL.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "publish ${value}"
  git -C "${SEED}" push -q origin main
}

# ── Install when missing ──────────────────────────────────────────────────────

@test "up: clones a configured module that is not installed yet" {
  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: not installed — cloning"
  assert_output --partial "external modules: 1 updated, 0 up to date, 0 local"
  [ -d "${DEST}/.git" ]
  [ "$(cat "${DEST}/skills/SKILL.md")" = "v1" ]
}

@test "up: renders the storage mirror for a freshly cloned module" {
  run bash "${SCRIPT}"

  assert_success
  [ -L "${STORAGE}/skills" ]
  [ "$(cat "${STORAGE}/skills/SKILL.md")" = "v1" ]
}

# ── Up-to-date clone ──────────────────────────────────────────────────────────

@test "up: leaves a module already at the remote commit alone" {
  preclone
  local before
  before="$(git -C "${DEST}" rev-parse HEAD)"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: up to date"
  assert_output --partial "external modules: 0 updated, 1 up to date, 0 local"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${before}" ]
}

# ── Update when the remote moved ──────────────────────────────────────────────

@test "up: fetches and hard-resets a module whose remote moved" {
  preclone
  publish v2
  local remote_head
  remote_head="$(git -C "${ORIGIN}" rev-parse main)"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: remote moved — updating"
  assert_output --partial "external modules: 1 updated, 0 up to date, 0 local"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${remote_head}" ]
  [ "$(cat "${DEST}/skills/SKILL.md")" = "v2" ]
}

@test "up: prunes a README restored by the update reset" {
  preclone
  printf 'new readme\n' > "${SEED}/skills/README.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "add readme"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  [ ! -e "${DEST}/skills/README.md" ]
}

@test "up: re-renders the storage mirror so a lifecycle script gained upstream is wired" {
  preclone
  printf '#!/usr/bin/env bash\n' > "${SEED}/reset.sh"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "add reset.sh"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  [ -L "${STORAGE}/reset.sh" ]
}

# ── Shared clones (several entries, one repo) ─────────────────────────────────

@test "up: renders a mirror for every entry sharing one clone on a fresh install" {
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "external modules: 1 updated, 0 up to date, 0 local"
  [ -L "${STORAGE}/skills" ]
  [ -L "${DEVROOT}/storage/external-agentic-modules/mod1-alias/agents" ]
}

@test "up: wires every entry of a fresh shared clone into the project" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${SCRIPT}" "${project}"

  assert_success
  [ -L "${project}/.agents/skills/mod1" ]
  [ -L "${project}/.agents/agents/mod1-alias" ]
}

@test "up: wires an entry that has a checkout but no mirror yet" {
  # The checkout predates this run (so no clone happens), and init.sh never
  # provisioned it: its mirror and project link must appear together.
  preclone
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"

  run bash "${SCRIPT}" "${project}"

  assert_success
  [ -L "${STORAGE}/skills" ]
  [ -L "${project}/.agents/skills/mod1" ]
}

@test "up: prunes the README of every entry sharing one clone after an update" {
  preclone
  publish v2
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${SCRIPT}"

  assert_success
  # Entry 1's reset restores both tracked READMEs; the co-tenant entry must
  # still prune its own paths.
  [ ! -e "${DEST}/skills/README.md" ]
  [ ! -e "${DEST}/agents/README.md" ]
}

# ── Skips and failures never block the start ──────────────────────────────────

@test "up: skips local-path modules — there is no remote" {
  mkdir -p "${SANDBOX}/local/skills"
  write_config '{"external_modules":{"mod1":{"local_path":"'"${SANDBOX}/local"'","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: local path — nothing to update"
  assert_output --partial "external modules: 0 updated, 0 up to date, 1 local"
  [ ! -d "${DEST}" ]
}

@test "up: does nothing when auto_update is false" {
  write_config '{"auto_update":false,"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "auto_update=false — external modules not checked"
  [ ! -d "${DEST}" ]
}

@test "up: warns but succeeds when the remote is unreachable" {
  preclone
  local before
  before="$(git -C "${DEST}" rev-parse HEAD)"
  rm -rf "${ORIGIN}"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: could not compare with the remote"
  assert_output --partial "1 uncomparable"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${before}" ]
}

@test "up: warns but succeeds when the tracked branch is gone upstream" {
  preclone
  local before
  before="$(git -C "${DEST}" rev-parse HEAD)"
  git -C "${ORIGIN}" update-ref -d refs/heads/main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: could not compare with the remote"
  assert_output --partial "1 uncomparable"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${before}" ]
}

@test "up: warns but succeeds when the update fetch itself fails" {
  preclone
  publish v2
  install_failing_fetch_git

  run env PATH="${SANDBOX}/bin:${PATH}" bash "${SCRIPT}"

  assert_success
  assert_output --partial "mod1: remote moved — updating"
  assert_output --partial "Failed to update mod1"
  assert_output --partial "1 failed"
}

@test "up: provisions a co-tenant of a clone whose update fetch failed" {
  preclone
  publish v2
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'
  install_failing_fetch_git

  run env PATH="${SANDBOX}/bin:${PATH}" bash "${SCRIPT}"

  assert_success
  # The alias must not repeat the fetch that just failed...
  [ "$(grep -c '^fetch$' "${SANDBOX}/git.log")" -eq 1 ]
  # ...but it still gets its mirror from the checkout that is present.
  [ -L "${DEVROOT}/storage/external-agentic-modules/mod1-alias/agents" ]
}

# Shim git to fail on fetch only: ls-remote still reports the new commit, the
# fetch fails, and the start must survive it. Every call is logged so a test
# can assert how many fetches were attempted.
install_failing_fetch_git() {
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\${arg}" == "fetch" ]]; then
    echo fetch >> "${SANDBOX}/git.log"
    echo "simulated fetch failure" >&2
    exit 1
  fi
done
exec "$(command -v git)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/git"
}

@test "up: re-renders a co-tenant mirror when the update adds a lifecycle script" {
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'
  # First start creates both mirrors from the current checkout.
  run bash "${SCRIPT}"
  assert_success
  [ ! -e "${DEVROOT}/storage/external-agentic-modules/mod1-alias/reset.sh" ]

  printf '#!/usr/bin/env bash\n' > "${SEED}/reset.sh"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "add reset.sh"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  # The alias's mirror existed already: the update must still refresh it, or
  # its new lifecycle script would never be wired.
  [ -L "${DEVROOT}/storage/external-agentic-modules/mod1-alias/reset.sh" ]
}

# ── Concurrency ───────────────────────────────────────────────────────────────

@test "up: does not block on an update lock held by another session" {
  preclone
  mkdir -p "$(dirname "${DEST}")"
  python3 - "${DEST}.lock" "${SANDBOX}/lock-ready" <<'PY' &
import fcntl
import sys
import time

handle = open(sys.argv[1], "w")
fcntl.flock(handle, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)
PY
  local locker=$!
  local i
  for i in $(seq 1 100); do
    [[ -f "${SANDBOX}/lock-ready" ]] && break
    sleep 0.1
  done

  run env DEV_BOT_MODULE_UPDATE_LOCK_WAIT=1 bash "${SCRIPT}"
  kill "${locker}" 2>/dev/null || true

  assert_success
  assert_output --partial "waiting for lock"
  assert_output --partial "mod1: up to date"
}

@test "up: reports no modules rather than failing when none are configured" {
  write_config '{"external_modules":{}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "No external modules configured"
}

@test "up: kills a stalled transport at the cap instead of hanging the start" {
  preclone
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "ls-remote" ]]; then
  # A transport that ignores TERM, in the same process group, holding the
  # caller's pipe: only a group KILL frees the start.
  bash -c 'trap "" TERM; sleep 60' &
  trap "" TERM
  sleep 60
fi
exec "$(command -v git)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/git"

  local started=${SECONDS}
  run env PATH="${SANDBOX}/bin:${PATH}" DEV_BOT_FETCH_TIMEOUT=2 bash "${SCRIPT}"
  local elapsed=$((SECONDS - started))

  assert_success
  assert_output --partial "mod1: could not compare with the remote"
  # 2s cap + 2s TERM->KILL grace, with room for slow CI machines.
  [ "${elapsed}" -le 10 ]
}

@test "up: a failed clone leaves no partial checkout and recovers on the next run" {
  # git shim: create a half-initialised target, then fail.
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "clone" ]]; then
  target="\${@: -1}"
  mkdir -p "\${target}/.git"
  exit 1
fi
exec "$(command -v git)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/git"

  run env PATH="${SANDBOX}/bin:${PATH}" bash "${SCRIPT}"

  assert_success
  assert_output --partial "Failed to clone mod1"
  [ ! -e "${DEST}" ]
  # No scratch clone left beside the destination either.
  [ -z "$(find "$(dirname "${DEST}")" -maxdepth 1 -name '.mod1.clone.*' 2>/dev/null)" ]

  # The next run, with real git, installs it: nothing to clean up by hand.
  run bash "${SCRIPT}"

  assert_success
  [ -d "${DEST}/.git" ]
}

@test "up: reports a failed install when the clone cannot be moved into place" {
  # python3 is shimmed to fail only on the rename call: the clone succeeds into
  # the scratch dir, the install does not, and the run must not claim success.
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/python3" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\${arg}" in
    *os.rename*) echo "simulated rename failure" >&2; exit 1 ;;
  esac
done
exec "$(command -v python3)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/python3"

  run env PATH="${SANDBOX}/bin:${PATH}" bash "${SCRIPT}"

  assert_success
  assert_output --partial "Failed to clone mod1: could not install it at"
  assert_output --partial "1 failed"
  [ ! -e "${DEST}" ]
}

@test "up: leaves no orphaned watchdog timer after a warm call" {
  preclone
  # A `sleep` shim records each timer's pid, so the assertion does not depend
  # on anything else running on the machine.
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/sleep" <<EOF
#!/usr/bin/env bash
echo "\$\$" >> "${SANDBOX}/sleeps.log"
exec "$(command -v sleep)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/sleep"

  run env PATH="${SANDBOX}/bin:${PATH}" DEV_BOT_FETCH_TIMEOUT=60 bash "${SCRIPT}"

  assert_success
  [ -s "${SANDBOX}/sleeps.log" ] || fail "the timer's sleep was never started"
  local pid alive=0
  for pid in $(cat "${SANDBOX}/sleeps.log"); do
    kill -0 "${pid}" 2>/dev/null && alive=1
  done
  [ "${alive}" -eq 0 ]
}

@test "up: kills a TERM-ignoring descendant left behind by a finished command" {
  preclone
  # The fake transport's leader exits at once; its child ignores TERM and
  # lingers 4s holding the caller's pipe.
  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "ls-remote" ]]; then
  bash -c 'trap "" TERM; sleep 4' &
  exit 0
fi
exec "$(command -v git)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/git"

  local started=${SECONDS}
  run env PATH="${SANDBOX}/bin:${PATH}" DEV_BOT_FETCH_TIMEOUT=30 bash "${SCRIPT}"
  local elapsed=$((SECONDS - started))

  assert_success
  assert_output --partial "mod1: could not compare with the remote"
  # TERM at the leader's exit, KILL 1s later — not the child's own 4s.
  [ "${elapsed}" -le 3 ]
}

@test "up: wires a module cloned during the start into the project" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"

  run bash "${SCRIPT}" "${project}"

  assert_success
  assert_output --partial "mod1: not installed — cloning"
  assert_output --partial "wiring external modules into the project"
  [ -L "${project}/.agents/skills/mod1" ]
  [ "$(readlink "${project}/.agents/skills/mod1")" = "${DEST}/skills" ]
}

@test "up: refuses a second repository that maps to the same vendor path" {
  # The vendor path drops the host, so these two URLs derive the same
  # destination while naming different repos.
  write_config '{"external_modules":{
    "local-one":{"url":"file://'"${ORIGIN}"'","paths":{"skills":"skills"}},
    "localhost-one":{"url":"file://localhost'"${ORIGIN}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "is already used by"
  assert_output --partial "1 failed"
  # The winning entry installed, and the loser was not provisioned from it.
  [ -L "${DEVROOT}/storage/external-agentic-modules/local-one/skills" ]
  [ ! -e "${DEVROOT}/storage/external-agentic-modules/localhost-one" ]
}

@test "up: refuses a checkout whose origin is a different repository" {
  preclone
  # A retained clone of another repo at this derived path: mirroring it under
  # this entry's name would install the wrong code.
  git -C "${DEST}" remote set-url origin "file://${SANDBOX}/other.git"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "belongs to"
  assert_output --partial "1 failed"
  [ ! -e "${STORAGE}" ]
}

@test "up: treats ssh and https spellings of one repository as the same remote" {
  run _normalize_remote_url "git@github.com:acme/repo.git"
  [ "${output}" = "https://github.com/acme/repo" ]

  run _normalize_remote_url "ssh://git@github.com/acme/repo"
  [ "${output}" = "https://github.com/acme/repo" ]

  run _normalize_remote_url "https://github.com/acme/repo.git"
  [ "${output}" = "https://github.com/acme/repo" ]

  # A rotated token must not read as a different repository.
  run _normalize_remote_url "https://user:old-token@github.com/acme/repo.git"
  [ "${output}" = "https://github.com/acme/repo" ]
}

@test "up: refuses a checkout with no origin remote" {
  preclone
  git -C "${DEST}" remote remove origin

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "has no origin remote"
  assert_output --partial "1 failed"
  [ ! -e "${STORAGE}" ]
}

@test "up: wiring a startup clone does not link an entry this run rejected" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"
  # A colliding entry whose repository is a different one: it must stay unwired.
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "localhost-one":{"url":"file://localhost'"${ORIGIN}"'","paths":{"agents":"agents"}}
  }}'

  run bash "${SCRIPT}" "${project}"

  assert_success
  [ -L "${project}/.agents/skills/mod1" ]
  [ ! -e "${project}/.agents/agents/localhost-one" ]
}

@test "up: falls back to the default cap when DEV_BOT_FETCH_TIMEOUT is not a positive number" {
  run _external_module_fetch_timeout
  [ "${output}" = "20" ]

  DEV_BOT_FETCH_TIMEOUT=5 run _external_module_fetch_timeout
  [ "${output}" = "5" ]

  DEV_BOT_FETCH_TIMEOUT=abc run _external_module_fetch_timeout
  [ "${output}" = "20" ]

  DEV_BOT_FETCH_TIMEOUT=0 run _external_module_fetch_timeout
  [ "${output}" = "20" ]
}

@test "up: redacts credentials before a URL reaches a warning" {
  run _redact_url "https://user:token@github.com/acme/repo.git"
  [ "${output}" = "https://***@github.com/acme/repo.git" ]

  run _redact_url "https://github.com/acme/repo.git"
  [ "${output}" = "https://github.com/acme/repo.git" ]
}

@test "up: derives one vendor path for every spelling of a repository" {
  run _derive_vendor_path "https://github.com/acme/repo.git"
  [ "${output}" = "acme/repo" ]

  run _derive_vendor_path "ssh://git@github.com/acme/repo"
  [ "${output}" = "acme/repo" ]

  run _derive_vendor_path "git@github.com:acme/repo.git"
  [ "${output}" = "acme/repo" ]

  run _derive_vendor_path "https://user:token@github.com/acme/repo.git"
  [ "${output}" = "acme/repo" ]
}

# ── Check interval ────────────────────────────────────────────────────────────

@test "up: checks at most once per interval" {
  preclone
  local stamp="${DEVROOT}/storage/run/external-modules.checked"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  assert_output --partial "mod1: up to date"
  [ -f "${stamp}" ]

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  assert_output --partial "last check"
  refute_output --partial "mod1: up to date"
}

@test "up: re-checks once the stamp is older than the interval" {
  preclone
  local stamp="${DEVROOT}/storage/run/external-modules.checked"
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  mkdir -p "$(dirname "${stamp}")"
  printf '%s\n' $(( $(date +%s) - 90000 )) > "${stamp}"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  assert_output --partial "mod1: up to date"
}

@test "up: does not stamp a check that could not reach a remote" {
  write_config '{"external_modules":{"mod1":{"url":"file://'"${SANDBOX}"'/gone.git","paths":{"skills":"skills"}}}}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  assert_output --partial "1 failed"
  [ ! -e "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "up: compares destinations in parallel" {
  # Four remotes; each ls-remote blocks until all four are in flight, so this
  # only passes when the checks actually run concurrently (no timing threshold
  # that load can break).
  local i path sep="" config='{"external_modules":{'
  for i in 1 2 3 4; do
    path="${SANDBOX}/remote-${i}.git"
    git init --bare -q --initial-branch=main "${path}"
    git -C "${SEED}" push -q "${path}" main
    mkdir -p "$(dirname "${DEVROOT}/vendor/$(_derive_vendor_path "file://${path}")")"
    git clone -q --depth 1 "file://${path}" "${DEVROOT}/vendor/$(_derive_vendor_path "file://${path}")"
    config+="${sep}\"m${i}\":{\"url\":\"file://${path}\",\"paths\":{\"skills\":\"skills\"}}"
    sep=","
  done
  write_config "${config}"'}}'

  mkdir -p "${SANDBOX}/bin"
  cat > "${SANDBOX}/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "ls-remote" ]]; then
  : > "${SANDBOX}/arrived.\$\$"
  for i in \$(seq 1 100); do
    if [[ "\$(ls "${SANDBOX}"/arrived.* 2>/dev/null | wc -l)" -ge 4 ]]; then
      : > "${SANDBOX}/parallel-ok"
      break
    fi
    sleep 0.1
  done
fi
exec "$(command -v git)" "\$@"
EOF
  chmod +x "${SANDBOX}/bin/git"

  run env PATH="${SANDBOX}/bin:${PATH}" bash "${SCRIPT}"

  assert_success
  assert_output --partial "4 up to date"
  [ -f "${SANDBOX}/parallel-ok" ]
}

# ── Path validation on update ─────────────────────────────────────────────────

@test "up: cancels an update whose configured path disappeared upstream" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"
  run bash "${SCRIPT}" "${project}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  # Upstream moves skills/ away; the config still points at it.
  git -C "${SEED}" rm -rq skills
  printf 'moved\n' > "${SEED}/skills.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "move skills"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}" "${project}"

  assert_success
  assert_output --partial "configured path 'skills=skills' is missing in the incoming version"
  assert_output --partial "update cancelled — keeping the current checkout"
  assert_output --partial "1 failed"
  # The legacy checkout and everything pointing into it are untouched.
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
  [ -f "${STORAGE}/skills/SKILL.md" ]
  [ -f "${project}/.agents/skills/mod1/SKILL.md" ]
}

@test "up: cancels an update when a configured file mapping disappeared upstream" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills","memory":{"skills/SKILL.md":"bootstrap/sk.md"}}}}}'
  run bash "${SCRIPT}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  git -C "${SEED}" rm -q skills/SKILL.md
  git -C "${SEED}" commit -qm "drop the skill file"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'memory=skills/SKILL.md' is missing"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
}

@test "up: cancels a first install whose configured path is missing" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"no-such-dir"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'skills=no-such-dir' is missing"
  assert_output --partial "install cancelled"
  assert_output --partial "1 failed"
  [ ! -e "${DEST}" ]
  [ ! -e "${STORAGE}" ]
}

@test "up: cancels an update that would drop an alias entry's configured path" {
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod1-alias":{"url":"'"${URL}"'","paths":{"agents":"agents"}}
  }}'
  run bash "${SCRIPT}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  # The first entry's path survives; the alias's does not.
  git -C "${SEED}" rm -rq agents
  git -C "${SEED}" commit -qm "drop agents"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'agents=agents' is missing in the incoming version"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -d "${DEST}/agents" ]
  [ -L "${DEVROOT}/storage/external-agentic-modules/mod1-alias/agents" ]
}

@test "up: processes a newly declared module despite a fresh stamp" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  assert_output --partial "mod1: up to date"

  # A second module appears after the stamp was written.
  second="${SANDBOX}/second.git"
  git init --bare -q --initial-branch=main "${second}"
  git -C "${SEED}" push -q "${second}" main
  write_config '{"external_modules":{
    "mod1":{"url":"'"${URL}"'","paths":{"skills":"skills"}},
    "mod2":{"url":"file://'"${second}"'","paths":{"skills":"skills"}}
  }}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -d "${DEVROOT}/storage/external-agentic-modules/mod2" ]
  [ -d "${DEVROOT}/vendor/$(_derive_vendor_path "file://${second}")/.git" ]
}

@test "up: repairs a missing checkout despite a fresh stamp" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  rm -r "${DEST}"
  git -C "${SEED}" status >/dev/null 2>&1 # keep the seed untouched

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -d "${DEST}/.git" ]
}

@test "up: repairs a missing mirror despite a fresh stamp" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  rm -r "${STORAGE}"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/skills" ]
}

@test "up: processes an edited configuration despite a fresh stamp" {
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  # Same module, a different configured path.
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"agents":"agents"}}}}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/agents" ]
}

@test "up: rebuilds a deleted local module mirror despite a fresh stamp" {
  mkdir -p "${SANDBOX}/local-source/skills"
  printf 'local\n' > "${SANDBOX}/local-source/skills/SKILL.md"
  write_config '{"external_modules":{"local-one":{"local_path":"'"${SANDBOX}"'/local-source","paths":{"skills":"skills"}}}}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  local mirror="${DEVROOT}/storage/external-agentic-modules/local-one"
  [ -L "${mirror}/skills" ]

  rm -r "${mirror}"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${mirror}/skills" ]
}

@test "up: does not wire a module the project disables" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}"
  printf '{"devbot_dir": ".agents", "modules": {"mod1": false}}\n' > "${project}/.devbot.project.jsonc"

  run bash "${SCRIPT}" "${project}"

  assert_success
  assert_output --partial "mod1: disabled — skipping wiring"
  # Provisioning is enablement-independent: the clone and mirror still exist.
  [ -d "${DEST}/.git" ]
  [ -L "${STORAGE}/skills" ]
  # Per-project wiring is not.
  [ ! -e "${project}/.agents/skills/mod1" ]
}

@test "up: repairs a mirror entry deleted under an intact mirror root" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  rm "${STORAGE}/skills" # the root stays, one configured entry goes

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/skills" ]
}

@test "up: refuses a URL that would map outside the vendor root" {
  write_config '{"external_modules":{"escape":{"url":"file://'"${SANDBOX}"'/../../outside.git","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "does not map inside vendor/"
  assert_output --partial "1 failed"
  [ ! -e "${SANDBOX}/../outside" ]
}

@test "up: refuses a module name that is not a single path component" {
  write_config '{"external_modules":{"../escape":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "invalid module name"
  assert_output --partial "1 failed"
  [ ! -e "${SANDBOX}/escape" ]
}

@test "up: redacts credentials in the rejected-URL warning" {
  write_config '{"external_modules":{"escape":{"url":"https://user:secret@example.com/../../outside.git","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "does not map inside vendor/"
  refute_output --partial "secret"
}

@test "up: repairs a deleted lifecycle link under an intact mirror root" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  [ -L "${STORAGE}/pre.sh" ]

  rm "${STORAGE}/pre.sh"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/pre.sh" ]
}

@test "up: renders a lifecycle-only module (empty paths map)" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{}}}}'

  run bash "${SCRIPT}"

  assert_success
  # The mirror root exists and holds the lifecycle links, with no paths map.
  [ -d "${STORAGE}" ]
  [ -L "${STORAGE}/pre.sh" ]
  [ "$(readlink "${STORAGE}/pre.sh")" = "${DEST}/pre.sh" ]
}

@test "up: repairs a lifecycle-only module whose mirror root was deleted" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{}}}}'
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  [ -L "${STORAGE}/pre.sh" ]

  rm -r "${STORAGE}"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/pre.sh" ]
}

@test "up: refuses a malformed paths map instead of resetting onto it" {
  local legacy
  preclone
  legacy="$(git -C "${DEST}" rev-parse HEAD)"
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":[]}}}'
  # A new upstream commit is available; the update must not apply it.
  printf 'v2\n' > "${SEED}/skills/SKILL.md"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm v2
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "invalid paths config"
  assert_output --partial "1 failed"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
}

@test "up: rejects a module name carrying the entry delimiter" {
  write_config "$(printf '{"external_modules":{"bad\\u001fname":{"url":"%s","paths":{"skills":"skills"}}}}' "${URL}")"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "invalid module name"
  assert_output --partial "1 failed"
}

@test "up: rejects a module name carrying a newline" {
  write_config "$(printf '{"external_modules":{"bad\\u000aname":{"url":"%s","paths":{"skills":"skills"}}}}' "${URL}")"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "invalid module name"
  assert_output --partial "1 failed"
}

@test "up: catches a repointed checkout origin despite a fresh stamp" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  git -C "${DEST}" remote set-url origin "file://${SANDBOX}/other.git"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  assert_output --partial "belongs to"
}

@test "up: cancels an update that turns a configured directory into a file" {
  preclone
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  git -C "${SEED}" rm -rq skills
  printf 'now a file\n' > "${SEED}/skills"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "skills becomes a file"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'skills=skills'"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
}

@test "up: cancels an update that turns a mapped file into a directory" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills","memory":{"skills/SKILL.md":"bootstrap/sk.md"}}}}}'
  run bash "${SCRIPT}"
  assert_success
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  git -C "${SEED}" rm -q skills/SKILL.md
  mkdir -p "${SEED}/skills/SKILL.md"
  printf 'x\n' > "${SEED}/skills/SKILL.md/nested"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "SKILL.md becomes a directory"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'memory=skills/SKILL.md'"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -f "${DEST}/skills/SKILL.md" ]
}

@test "up: repairs an incomplete mirror even without a stamp" {
  preclone
  run env DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL=0 bash "${SCRIPT}"
  assert_success
  [ -L "${STORAGE}/skills" ]

  rm "${DEVROOT}/storage/run/external-modules.checked"
  rm "${STORAGE}/skills"

  run env DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL=0 bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ -L "${STORAGE}/skills" ]
}

@test "up: a quote in a configured path cannot break or execute the parser" {
  local marker="${SANDBOX}/pwned"
  # Closing the interpolated python string and running code: it must stay data.
  local evil="x') or __import__('os').system('touch ${marker}') or ('"
  write_config "{\"external_modules\":{\"mod1\":{\"url\":\"${URL}\",\"paths\":{\"skills\":\"${evil}\"}}}}"

  run bash "${SCRIPT}"

  assert_success
  [ ! -e "${marker}" ]
}

@test "up: refuses to nest a scratch clone into an existing destination" {
  mkdir -p "${DEST}"
  printf 'existing\n' > "${DEST}/file.txt"

  run _external_module_install_dir "${SANDBOX}" "${DEST}"

  assert_failure
  [ ! -d "${DEST}/$(basename "${SANDBOX}")" ]
  [ -f "${DEST}/file.txt" ]
}

@test "up: does not wire a module whose mirror render failed" {
  local project="${SANDBOX}/project"
  mkdir -p "${project}" "${DEVROOT}/storage/external-agentic-modules"
  printf '{"devbot_dir": ".agents"}\n' > "${project}/.devbot.project.jsonc"
  # Make the mirror root un-creatable: a file where the module dir must be.
  : > "${DEVROOT}/storage/external-agentic-modules/mod1"

  run bash "${SCRIPT}" "${project}"

  assert_success
  assert_output --partial "mirror render failed"
  [ ! -e "${project}/.agents/skills/mod1" ]
}

@test "up: a configured source that is absent fails the render and the stamp" {
  preclone
  # The checkout is current; the config points at a path it does not have.
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"missing-dir"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mirror render failed"
  assert_output --partial "1 failed"
  [ ! -e "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "up: a mirror entry pointing somewhere else is re-rendered" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  # Same link name, wrong target: existence alone must not satisfy the probe.
  rm "${STORAGE}/skills"
  ln -s "${SANDBOX}/elsewhere" "${STORAGE}/skills"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  [ "$(readlink "${STORAGE}/skills")" = "${DEST}/skills" ]
}

@test "up: a regular file in a mirror's way is reported, not stamped over" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  rm "${STORAGE}/skills"
  printf 'not a link\n' > "${STORAGE}/skills"
  rm -f "${DEVROOT}/storage/run/external-modules.checked"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "exists but not symlink"
  assert_output --partial "mirror render failed"
  assert_output --partial "1 failed"
  [ ! -f "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "up: a dangling mirror link is not healthy" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  [ -L "${STORAGE}/skills" ]

  # The source behind the link disappears: the link text still matches, so
  # only an existence check on the target can catch this.
  rm -r "${DEST}/skills"
  rm -f "${DEVROOT}/storage/run/external-modules.checked"

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  assert_output --partial "mirror render failed"
  [ ! -f "${DEVROOT}/storage/run/external-modules.checked" ]
}

@test "up: a module literally named __invalid_name__ is installed normally" {
  write_config '{"external_modules":{"__invalid_name__":{"url":"'"${URL}"'","paths":{"skills":"skills"}}}}'

  run bash "${SCRIPT}"

  assert_success
  refute_output --partial "invalid module name"
  [ -L "${DEVROOT}/storage/external-agentic-modules/__invalid_name__/skills" ]
}

@test "up: refuses traversal in a configured path" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"../../outside"}}}}'

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "invalid paths config"
  assert_output --partial "1 failed"
  [ ! -e "${SANDBOX}/outside" ]
}

@test "up: refuses traversal in a path key or a mapped destination" {
  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"../escape":"skills"}}}}'
  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "invalid paths config"

  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":{"skills":"skills","memory":{"skills/SKILL.md":"../../evil"}}}}}'
  run bash "${SCRIPT}"
  assert_success
  assert_output --partial "invalid paths config"
  [ ! -e "${SANDBOX}/evil" ]
}

@test "up: a directory where a lifecycle link belongs is not deleted" {
  preclone
  rm -r "${DEVROOT}/storage/external-agentic-modules" 2>/dev/null || true
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success
  [ -L "${STORAGE}/pre.sh" ]

  rm "${STORAGE}/pre.sh"
  mkdir -p "${STORAGE}/pre.sh"
  printf 'user data\n' > "${STORAGE}/pre.sh/keep.txt"
  rm -f "${DEVROOT}/storage/run/external-modules.checked"

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "mirror render failed"
  # The conflicting directory and its contents survive.
  [ -f "${STORAGE}/pre.sh/keep.txt" ]
}

@test "up: a malformed paths map cannot satisfy a fresh stamp" {
  preclone
  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"
  assert_success

  write_config '{"external_modules":{"mod1":{"url":"'"${URL}"'","paths":[]}}}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  refute_output --partial "last check"
  assert_output --partial "invalid paths config"
}

@test "up: rejects a configured directory that became a symlink to a file" {
  preclone
  local legacy
  legacy="$(git -C "${DEST}" rev-parse HEAD)"

  git -C "${SEED}" rm -rq skills
  ln -s agents/AGENT.md "${SEED}/skills"
  git -C "${SEED}" add -A
  git -C "${SEED}" commit -qm "skills becomes a symlink"
  git -C "${SEED}" push -q origin main

  run bash "${SCRIPT}"

  assert_success
  assert_output --partial "configured path 'skills=skills'"
  assert_output --partial "update cancelled — keeping the current checkout"
  [ "$(git -C "${DEST}" rev-parse HEAD)" = "${legacy}" ]
  [ -d "${DEST}/skills" ]
}

@test "up: a missing local source fails the run and writes no stamp" {
  write_config '{"external_modules":{"local-one":{"local_path":"'"${SANDBOX}"'/gone","paths":{"skills":"skills"}}}}'

  run env -u DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL bash "${SCRIPT}"

  assert_success
  assert_output --partial "local path not found"
  assert_output --partial "1 failed"
  [ ! -f "${DEVROOT}/storage/run/external-modules.checked" ]
}
