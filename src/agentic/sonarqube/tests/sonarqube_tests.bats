#!/usr/bin/env bats
# =============================================================================
# src/agentic/sonarqube/tests/sonarqube_tests.bats
# Tests for the sonarqube module (official SonarQube MCP server + official
# agent skills).
#
# The MCP server is the official `sonarsource/sonarqube-mcp` container launched
# over stdio by serve.mcp.sh. One container per harness instance, started only
# when the MCP entry is enabled (the module ships it `enabled: false`).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  SHARED_DIR="$(cd "${MODULE_DIR}/../../_shared" && pwd)"
}

# ── MCP manifest ─────────────────────────────────────────────────────────────

@test "canonical mcp.json declares a docker-backed stdio server, wired but not started" {
  run python3 -c "
import json
m = json.load(open('${MODULE_DIR}/mcp.json'))['mcp']['sonarqube']
assert m['type'] == 'stdio', m
assert m['enabled'] is False, m
assert 'url' not in m, m
assert m['command'][0] == 'bash' and m['command'][1] == '-c', m
assert '{harness-dir}/sonarqube-serve.mcp.sh' in m['command'][2], m
assert m['env']['SONARQUBE_TOKEN'] == '{env:SONARQUBE_TOKEN}', m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "the manifest raises the MCP startup timeout above opencode's 30 s default" {
  # Container boot plus analyzer sync measured at 29-46 s, so the default
  # startup timeout reports the enabled server as failed.
  run python3 -c "
import json
m = json.load(open('${MODULE_DIR}/mcp.json'))['mcp']['sonarqube']
assert m.get('timeout') == 120000, m
print('TIMEOUT:OK')
"
  assert_success
  grep -qF 'TIMEOUT:OK' <<< "$output" || fail "manifest startup timeout wrong"
}

@test "the manifest translates for both harnesses" {
  local tool="${PROJECT_ROOT}/src/_shared/mcp_translate.py"

  run python3 "$tool" "${MODULE_DIR}/mcp.json" opencode
  assert_success
  assert_output --partial '"type": "local"'
  assert_output --partial '.opencode/sonarqube-serve.mcp.sh'
  assert_output --partial '"enabled": false'
  assert_output --partial '{env:SONARQUBE_TOKEN}'

  run python3 "$tool" "${MODULE_DIR}/mcp.json" claudecode
  assert_success
  assert_output --partial '"type": "stdio"'
  assert_output --partial '.claude/sonarqube-serve.mcp.sh'
  assert_output --partial '${SONARQUBE_TOKEN}'
}

@test "the env presence check sees SONARQUBE_TOKEN" {
  run python3 "${PROJECT_ROOT}/src/_shared/mcp_env_refs.py" "${MODULE_DIR}/mcp.json"
  assert_success
  assert_output --partial 'sonarqube	SONARQUBE_TOKEN	SONARQUBE_TOKEN'
}

# ── Lifecycle scripts ────────────────────────────────────────────────────────

@test "install/update/pre/init and the launcher exist, parse cleanly and are executable" {
  for s in install.sh update.sh pre.sh init.sh serve.mcp.sh; do
    [ -f "${MODULE_DIR}/$s" ]
    [ -x "${MODULE_DIR}/$s" ]
    run bash -n "${MODULE_DIR}/$s"
    assert_success
  done
}

@test "functions.sh sources the shared library" {
  run grep -q '_shared/functions.sh' "${MODULE_DIR}/functions.sh"
  assert_success
}

# ── Launcher ────────────────────────────────────────────────────────────────

@test "serve.mcp.sh refuses to launch without SONARQUBE_TOKEN" {
  run env -u SONARQUBE_TOKEN bash "${MODULE_DIR}/serve.mcp.sh"
  assert_failure
  assert_output --partial 'FATAL: SONARQUBE_TOKEN is unset'
}

@test "serve.mcp.sh forwards only configured optional vars and the pinned image" {
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" \
    SONARQUBE_TOKEN=tok \
    SONARQUBE_URL=https://sonarqube.example.com \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  grep -Fxq -- 'run' <<< "$output" || fail "docker run missing"
  grep -Fxq -- '--rm' <<< "$output" || fail "--rm missing"
  grep -Fxq -- '--pull=missing' <<< "$output" || fail "lazy pull policy missing"
  grep -Fxq -- 'SONARQUBE_TOKEN' <<< "$output" || fail "token forwarding missing"
  grep -Fxq -- 'SONARQUBE_URL' <<< "$output" || fail "url forwarding missing"
  refute grep -Fxq -- 'SONARQUBE_ORG' <<< "$output"
  grep -Fq -- '/app/mcp-workspace:ro' <<< "$output" || fail "workspace mount missing"
  grep -Fq -- 'sonarsource/sonarqube-mcp:' <<< "$output" || fail "image missing"

  rm -rf "${mockbin}"
}

@test "serve.mcp.sh persists the analyzer cache in a named volume" {
  # Without a persistent volume the server re-downloads its analyzers on every
  # start — the dominant cost of the cold start it must fit inside `timeout`.
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" SONARQUBE_TOKEN=tok \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  grep -Fq -- 'devbot-sonarqube-mcp-storage:/app/storage' <<< "$output" \
    || fail "persistent analyzer volume missing"

  rm -rf "${mockbin}"
}

@test "serve.mcp.sh omits the workspace mount when SONARQUBE_WORKSPACE_MOUNT=false" {
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" SONARQUBE_TOKEN=tok SONARQUBE_WORKSPACE_MOUNT=false \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  refute grep -Fq -- '/app/mcp-workspace' <<< "$output"

  rm -rf "${mockbin}"
}

@test "serve.mcp.sh honours SONARQUBE_WORKSPACE_MODE=rw" {
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" SONARQUBE_TOKEN=tok SONARQUBE_WORKSPACE_MODE=rw \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  grep -Fq -- '/app/mcp-workspace:rw' <<< "$output" || fail "rw mount mode not honoured"

  rm -rf "${mockbin}"
}

@test "serve.mcp.sh forwards every configured optional var" {
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" \
    SONARQUBE_TOKEN=tok \
    SONARQUBE_ORG=my-org \
    SONARQUBE_PROJECT_KEY=my-project \
    SONARQUBE_TOOLSETS=issues,quality-gates \
    SONARQUBE_READ_ONLY=true \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  for var in SONARQUBE_ORG SONARQUBE_PROJECT_KEY SONARQUBE_TOOLSETS SONARQUBE_READ_ONLY; do
    grep -Fxq -- "${var}" <<< "$output" || fail "${var} not forwarded"
  done

  rm -rf "${mockbin}"
}

@test "serve.mcp.sh honours SONARQUBE_MCP_IMAGE" {
  local mockbin
  mockbin="$(mktemp -d)"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" SONARQUBE_TOKEN=tok \
    SONARQUBE_MCP_IMAGE="registry.example.com/sonarqube-mcp:custom" \
    bash -c "cd '${MODULE_DIR}' && '${MODULE_DIR}/serve.mcp.sh'"

  assert_success
  grep -Fxq -- 'registry.example.com/sonarqube-mcp:custom' <<< "$output" || fail "image override ignored"

  rm -rf "${mockbin}"
}

# A PATH holding only the builtins' helpers: docker is absent, everything the
# scripts source still resolves.
_empty_path_with() {
  local dir="$1"
  shift
  ln -s "$(command -v bash)" "${dir}/bash"
  ln -s "$(command -v dirname)" "${dir}/dirname"
}

@test "serve.mcp.sh fails clearly when docker is missing" {
  local mockbin
  mockbin="$(mktemp -d)"
  _empty_path_with "${mockbin}"

  run env PATH="${mockbin}" SONARQUBE_TOKEN=tok bash "${MODULE_DIR}/serve.mcp.sh"
  assert_failure
  assert_output --partial 'FATAL: docker is required'

  rm -rf "${mockbin}"
}

@test "install.sh fails clearly when docker is missing" {
  local mockbin
  mockbin="$(mktemp -d)"
  _empty_path_with "${mockbin}"

  run env PATH="${mockbin}" bash "${MODULE_DIR}/install.sh"
  assert_failure
  assert_output --partial 'docker is required'

  rm -rf "${mockbin}"
}

# ── Image install / update ──────────────────────────────────────────────────

@test "install.sh verifies docker and never pulls an image (install stays cheap)" {
  local mockbin marker
  mockbin="$(mktemp -d)"
  marker="$(mktemp)"
  rm -f "${marker}"
  cat > "${mockbin}/docker" <<MOCK
#!/usr/bin/env bash
case "\$1" in
  --version) echo "Docker version test" ;;
  pull) touch "${marker}"; exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" bash "${MODULE_DIR}/install.sh"
  assert_success
  assert_output --partial 'pulled on the first MCP start'
  [ ! -e "${marker}" ]

  rm -rf "${mockbin}"
}

# A sandbox copy gives update.sh a private versions.env to rewrite.
_make_update_sandbox() {
  SANDBOX="$(mktemp -d)"
  MODULE_COPY="${SANDBOX}/src/agentic/sonarqube"
  mkdir -p "${MODULE_COPY}"
  cp -r "${MODULE_DIR}/." "${MODULE_COPY}/"
  ln -s "${SHARED_DIR}" "${SANDBOX}/src/_shared"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
}

@test "update.sh bumps the pin from Docker Hub and pulls the new image" {
  _make_update_sandbox
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
cat <<'JSON'
{"results":[{"name":"latest"},{"name":"2026.5.1"},{"name":"1.30.0.4763"},{"name":"1.31.2.5000"}]}
JSON
MOCK
  cat > "${MOCKBIN}/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Docker version test" ;;
  image) exit 0 ;;
  pull) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${MOCKBIN}/curl" "${MOCKBIN}/docker"

  run env PATH="${MOCKBIN}:${PATH}" bash "${MODULE_COPY}/update.sh"
  assert_success
  grep -q '^SONARQUBE_MCP_IMAGE_TAG=1\.31\.2\.5000$' "${MODULE_COPY}/versions.env" \
    || fail "pin was not bumped to the newest 1.x tag"

  rm -rf "${SANDBOX}"
}

@test "update.sh keeps the pin when the registry cannot be reached" {
  _make_update_sandbox
  local before
  before="$(grep '^SONARQUBE_MCP_IMAGE_TAG=' "${MODULE_COPY}/versions.env")"
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
  cat > "${MOCKBIN}/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Docker version test" ;;
  image) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${MOCKBIN}/curl" "${MOCKBIN}/docker"

  run env PATH="${MOCKBIN}:${PATH}" bash "${MODULE_COPY}/update.sh"
  assert_success
  assert_output --partial 'keeping the existing pin'
  [ "$(grep '^SONARQUBE_MCP_IMAGE_TAG=' "${MODULE_COPY}/versions.env")" = "${before}" ]

  rm -rf "${SANDBOX}"
}

@test "update.sh keeps the pin when the candidate image manifest is unavailable" {
  _make_update_sandbox
  local before
  before="$(grep '^SONARQUBE_MCP_IMAGE_TAG=' "${MODULE_COPY}/versions.env")"
  cat > "${MOCKBIN}/curl" <<'MOCK'
#!/usr/bin/env bash
cat <<'JSON'
{"results":[{"name":"latest"},{"name":"1.31.2.5000"}]}
JSON
MOCK
  cat > "${MOCKBIN}/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Docker version test" ;;
  manifest) exit 1 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${MOCKBIN}/curl" "${MOCKBIN}/docker"

  run env PATH="${MOCKBIN}:${PATH}" bash "${MODULE_COPY}/update.sh"
  assert_success
  assert_output --partial 'keeping the existing pin'
  [ "$(grep '^SONARQUBE_MCP_IMAGE_TAG=' "${MODULE_COPY}/versions.env")" = "${before}" ]

  rm -rf "${SANDBOX}"
}

# ── Per-project init ────────────────────────────────────────────────────────

@test "init.sh symlinks the launcher into .opencode and .claude" {
  local sandbox project mockbin
  sandbox="$(mktemp -d)"
  project="${sandbox}/project"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${project}" "${mockbin}"
  printf '{ "modules": { "opencode": true, "claudecode": true } }\n' > "${project}/.devbot.project.jsonc"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Docker version test" ;;
  image) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" bash "${MODULE_DIR}/init.sh" "${project}"
  assert_success
  [ -L "${project}/.opencode/sonarqube-serve.mcp.sh" ]
  [ -L "${project}/.claude/sonarqube-serve.mcp.sh" ]
  [ "$(readlink "${project}/.opencode/sonarqube-serve.mcp.sh")" = "${MODULE_DIR}/serve.mcp.sh" ]

  rm -rf "${sandbox}"
}

@test "init.sh honours a disabled harness module" {
  local sandbox project mockbin
  sandbox="$(mktemp -d)"
  project="${sandbox}/project"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${project}" "${mockbin}"
  printf '{ "modules": { "opencode": false, "claudecode": true } }\n' > "${project}/.devbot.project.jsonc"
  cat > "${mockbin}/docker" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Docker version test" ;;
  image) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "${mockbin}/docker"

  run env PATH="${mockbin}:${PATH}" bash "${MODULE_DIR}/init.sh" "${project}"
  assert_success
  [ ! -e "${project}/.opencode/sonarqube-serve.mcp.sh" ]
  [ -L "${project}/.claude/sonarqube-serve.mcp.sh" ]

  rm -rf "${sandbox}"
}

# ── Official skills + global default ────────────────────────────────────────

@test "external-modules.json declares the official SonarQube agent-plugins skills" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/external-modules.json'))
m = d['sonarqube-agent-plugins']
assert m['url'] == 'https://github.com/SonarSource/sonarqube-agent-plugins.git', m
assert m['paths']['skills'] == 'skills', m
print('SKILLS:OK')
"
  assert_success
  grep -qF 'SKILLS:OK' <<< "$output" || fail "external-modules declaration wrong"
}

@test "the distributed global config ships sonarqube disabled by default" {
  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${PROJECT_ROOT}/.devbot.global.dist.jsonc')
assert d['modules']['sonarqube'] is False, d['modules']
print('GLOBAL:OK')
"
  assert_success
  grep -qF 'GLOBAL:OK' <<< "$output" || fail "dist must ship sonarqube: false"
}

@test "docs.md has the required description and declares the MCP server" {
  [ -f "${MODULE_DIR}/docs.md" ]
  run grep -qE '^description: ' "${MODULE_DIR}/docs.md"
  assert_success
  run grep -qE '^  sonarqube: ' "${MODULE_DIR}/docs.md"
  assert_success
}
