#!/usr/bin/env bats
# =============================================================================
# src/agentic/kafka/tests/kafka_tests.bats
# Tests for the kafka module:
#   - render_config.py (the catalogue → mcp-confluent YAML renderer)
#   - init.sh (per-connection dynamic manifests, prune, module-disabled guard,
#     module memory)
#   - tools/kafka-mcp-launch.sh (connection resolution, credential export, the
#     allowlist, the startup preflight, refusal paths)
#   - the install pin's allowlist arithmetic (version floor, dropped tools)
#
# No network and no real broker: the npm binary is faked on PATH, and every
# fixture is a temp sandbox DEV_BOT_ROOT.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  REPO_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"

  RENDER="$MODULE_DIR/render_config.py"
  LAUNCHER="$MODULE_DIR/tools/kafka-mcp-launch.sh"
  INIT="$MODULE_DIR/init.sh"

  TMP="$(mktemp -d)"
  SANDBOX="$TMP/root"
  PROJECT="$TMP/project"
  RUNTIME="$TMP/runtime"
  BIN="$TMP/bin"
  mkdir -p "$SANDBOX" "$PROJECT" "$BIN"

  _fake_server
}

teardown() {
  rm -rf "$TMP"
}

# ── fixtures ──────────────────────────────────────────────────────────────────

# A catalogue entry with a named auth block, every reference supplied by `env`.
_STAGING='{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${MY_PASS}"}}}'

# The catalogue a machine declares: just the kafka_connections value.
_catalogue() {
  printf '%s\n' "$1" >"$TMP/catalogue.json"
}

# The global config the scripts read, wrapping the catalogue with the module on.
_global() {
  local modules='{"kafka": true}'
  if [[ -n "${1:-}" ]]; then
    modules="$1"
  fi
  printf '{"modules": %s, "kafka_connections": %s}\n' "${modules}" "$(cat "$TMP/catalogue.json")" \
    >"$SANDBOX/.devbot.global.jsonc"
}

# The project's opt-in list.
_project() {
  local names="" name
  for name in "$@"; do names="${names}${names:+,}\"${name}\""; done
  printf '{"project_name": "fixture", "harness": "opencode", "devbot_dir": ".agents", "kafka_connections": [%s]}\n' "${names}" \
    >"$PROJECT/.devbot.project.jsonc"
}

# A server binary that models the startup contract: it rejects the flag pair and
# the retired credential shape, answers `--list-tools` in the COLOURISED shape
# 1.6.1 emits (escapes between the indent, the name and the colon), and otherwise
# reports its argv and the environment it inherited.
_fake_server() {
  cat >"$BIN/mcp-confluent" <<'EOF'
#!/usr/bin/env bash
config=""
previous=""
for arg in "$@"; do
  if [[ "$previous" == "--config" ]]; then config="$arg"; fi
  previous="$arg"
done

# Every entry point logs the telemetry flag. The path is baked in: the server's
# environment is scrubbed, so it cannot be passed one.
printf 'TRACK:%s\n' "${DO_NOT_TRACK:-<unset>}" >>"__FAKE_LOG__"

case " $* " in
  *" --list-tools "*)
    printf 'kafka:\n'
    for tool in list-topics get-partition-offsets list-consumer-groups \
      describe-consumer-group get-consumer-group-lag consume-messages \
      produce-message; do
      # 1.6.1 colourises: indent, name and colon are each wrapped.
      printf '\033[2m  \033[0m\033[36m%s\033[0m\033[2m: \033[0mdoes a thing\n' "$tool"
    done
    printf 'schema-registry:\n\033[2m  \033[0m\033[36mlist-schemas\033[0m: does a thing\n'
    printf 'mcp-server-diagnostics:\n\033[2m  \033[0m\033[36mexplain-disabled-tools\033[0m: does a thing\n'
    exit 0
    ;;
  *" --version "*) echo "1.6.1"; exit 0 ;;
esac

# 1.6.1 rejects --config together with an explicit --transport.
case " $* " in
  *" --config "*" --transport "*)
    echo "Error: --config and --transport are mutually exclusive: use server.transports in the YAML file instead" >&2
    exit 1
    ;;
esac

# 1.6.1 rejects librdkafka credential keys inside extra_properties.
if [[ -n "$config" ]] && grep -qE '^[[:space:]]+(sasl\.username|sasl\.password|bootstrap\.servers):' "$config" 2>/dev/null; then
  echo "Error: extra_properties must not include sasl.username, sasl.password — use the named YAML fields (bootstrap_servers, auth) instead" >&2
  exit 1
fi

echo "ARGS:$*"
echo "TRACK:${DO_NOT_TRACK:-<unset>}"
echo "PASS:${KAFKA_PASS:-<unset>}"
echo "LEAK:${KAFKA_TEST_LEAK:-<unset>}"
echo "AUTHVAR:${KAFKA_AUTH_VAR:-<unset>}"
EOF
  chmod +x "$BIN/mcp-confluent"
  sed -i.bak "s|__FAKE_LOG__|${TMP}/seen-telemetry|" "$BIN/mcp-confluent"
  rm -f "$BIN/mcp-confluent.bak"
}

# A server that refuses every launch, to prove the preflight surfaces its message.
_rejecting_server() {
  cat >"$BIN/mcp-confluent" <<'EOF'
#!/usr/bin/env bash
echo "Error: connection 0 failed schema validation" >&2
exit 1
EOF
  chmod +x "$BIN/mcp-confluent"
}

_init() {
  env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$INIT" "$PROJECT"
}

_launch() {
  env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$LAUNCHER" "$@"
}

# The published config for a connection (content-addressed, so glob it).
_published() {
  printf '%s' "${RUNTIME}/$1-"*.yaml
}

_render() {
  env DEV_BOT_ROOT="$SANDBOX" python3 "$RENDER" "$@" <"$TMP/catalogue.json"
}

# ── render_config.py ──────────────────────────────────────────────────────────

@test "render: a connection becomes a read-only direct config with a named auth block" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "${K}", "secret": "${S}"}, "extra_properties": {"sasl.mechanisms": "SCRAM-SHA-512"}, "schema_registry": {"endpoint": "https://sr.local", "auth": {"type": "api_key", "key": "${SK}", "secret": "${SS}"}}}}'

  run _render staging

  assert_success
  assert_line "connections:"
  assert_line "  staging:"
  assert_line "    type: direct"
  # Defence in depth on top of --allow-tools.
  assert_line "    read_only: true"
  assert_line '      bootstrap_servers: "broker:9092"'
  assert_line "      auth:"
  assert_line "        type: \"api_key\""
  assert_line '        key: "${K}"'
  assert_line "      extra_properties:"
  assert_line '        sasl.mechanisms: "SCRAM-SHA-512"'
  assert_line "    schema_registry:"
  assert_line '      endpoint: "https://sr.local"'
  assert_line '        secret: "${SS}"'
}

@test "render: credentials never land in extra_properties" {
  # The server rejects sasl.username/password there, so a rendered config that
  # put them there would fail at launch — where the fix is far from the config.
  _catalogue "$_STAGING"

  run _render staging

  assert_success
  refute_output --partial "sasl.password"
  refute_line "      extra_properties:"
}

@test "render: a \${VAR} reference is left for the server to interpolate" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "${KAFKA_STAGING_USER}", "secret": "${KAFKA_STAGING_PASS}"}}}'

  run _render staging

  assert_success
  # Verbatim: the launcher exports the variable, the server substitutes it and
  # refuses to start when it is missing.
  assert_line '        secret: "${KAFKA_STAGING_PASS}"'
}

@test "render: a hostile broker string cannot change the document's shape" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092 # not-a-comment"}}'

  run _render staging

  assert_success
  assert_line '      bootstrap_servers: "broker:9092 # not-a-comment"'
  refute_line "-- not-a-comment"
}

@test "render: the launcher-only env block is not rendered" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${MY_PASS}"}}}'

  run _render staging

  assert_success
  # Unresolved on purpose: this mode never touches the environment.
  assert_line '        secret: "${MY_PASS}"'
  refute_output --partial "env:"
}

@test "render: an undeclared connection is refused by name" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'

  run _render production

  assert_failure
  assert_output --partial "connection 'production' is not declared in kafka_connections"
}

@test "render: a near-miss key is refused instead of silently ignored" {
  _catalogue '{"staging": {"bootstrap_server": "broker:9092"}}'

  run _render staging

  assert_failure
  assert_output --partial "unknown key(s) bootstrap_server"
}

@test "render: a non-string property is refused instead of emitted as a number" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "extra_properties": {"request.timeout.ms": 30}}}'

  run _render staging

  assert_failure
  assert_output --partial "staging.extra_properties.request.timeout.ms must be a string"
}

@test "render: a wrong-typed empty block is refused, not read as empty" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "extra_properties": []}}'

  run _render staging

  assert_failure
  assert_output --partial "staging.extra_properties must be an object of string values"
}

@test "render: a connection cannot set a launcher-owned variable" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "env": {"PATH": "/tmp/evil"}}}'

  run _render staging

  assert_failure
  # There is no env block any more, and no way to set a launcher variable.
  assert_output --partial "unknown key(s) env"
}

@test "render: a Schema Registry without an endpoint is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "schema_registry": {"auth": {"type": "api_key", "key": "a", "secret": "b"}}}}'

  run _render staging

  assert_failure
  assert_output --partial "schema_registry.endpoint must be a non-empty string"
}

@test "render: a Schema Registry extra_properties block is refused, not rendered" {
  # 1.6.1's registry block is strict: endpoint + auth only.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "schema_registry": {"endpoint": "https://sr", "extra_properties": {"a": "b"}}}}'

  run _render staging

  assert_failure
  assert_output --partial "schema_registry has unknown key(s) extra_properties"
}

@test "render: a non-URL Schema Registry endpoint is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "schema_registry": {"endpoint": "sr.local:8081"}}}'

  run _render staging

  assert_failure
  assert_output --partial "must be an http:// or https:// URL"
}

@test "render: an auth block without a secret is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k"}}}'

  run _render staging

  assert_failure
  assert_output --partial "staging.auth.secret must be a non-empty string"
}

@test "render: an unsupported auth type is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "oauth", "key": "k", "secret": "s"}}}'

  run _render staging

  assert_failure
  assert_output --partial 'staging.auth.type must be "api_key"'
}

# ── init.sh ───────────────────────────────────────────────────────────────────

@test "init: a selected connection becomes a disabled, secret-free manifest" {
  _catalogue "$_STAGING"
  _global
  _project staging

  run _init

  assert_success
  assert_output --partial "kafka-staging -> kafka-mcp-launch.sh staging"
  # The connection's env references an unset variable here: a reinit must still
  # wire it (the secret may live only where the harness starts), and must say so.
  assert_output --partial "resolves to nothing"
  assert [ -f "$PROJECT/.agents/mcp-runtime/kafka-staging.json" ]
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]

  run jq -r '."kafka-staging".enabled' "$PROJECT/.opencode/kafka-staging.mcp.json"
  assert_output "false"

  # The command names the connection and nothing else — no credential, and no
  # ${VAR} reference that a reader of the manifest could mistake for one.
  run jq -r '."kafka-staging".command[2]' "$PROJECT/.opencode/kafka-staging.mcp.json"
  assert_output --partial "kafka-mcp-launch.sh staging"
  refute_output --partial "KAFKA"
  refute_output --partial '${'
}

@test "init: a selected but undeclared connection warns and is not wired" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  _project staging ghost

  run _init

  assert_success
  assert_output --partial "'ghost' is selected but not declared"
  assert [ ! -f "$PROJECT/.opencode/kafka-ghost.mcp.json" ]
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "init: an unrenderable connection is not wired, and says why" {
  _catalogue '{"broken": {"bootstrap_server": "broker:9092"}}'
  _global
  _project broken

  run _init

  assert_success
  assert_output --partial "'broken' could not be wired"
  assert_output --partial "unknown key(s) bootstrap_server"
  assert [ ! -f "$PROJECT/.opencode/kafka-broken.mcp.json" ]
}

@test "init: a connection the installed server rejects is not wired" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  _project staging
  _rejecting_server

  run _init

  assert_success
  assert_output --partial "'staging' could not be wired"
  assert_output --partial "failed schema validation"
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "init: a selected glob does not wire a declared connection" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  # The project asks for "*", and a file named after the connection sits in the
  # working directory: expansion would wire what the project never selected.
  _project '*'
  : >"$PROJECT/staging"

  run bash -c "cd '$PROJECT' && env DEV_BOT_ROOT='$SANDBOX' KAFKA_RUNTIME_DIR='$RUNTIME' \
    PATH='$BIN:$PATH' bash '$INIT' '$PROJECT'"

  assert_success
  assert_output --partial "is not a valid connection name"
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "init: a devbot_dir with a space is escaped in the launch command" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  printf '{"project_name": "fixture", "harness": "opencode", "devbot_dir": ".agents dir", "kafka_connections": ["staging"]}\n' \
    >"$PROJECT/.devbot.project.jsonc"

  run _init

  assert_success
  run jq -r '."kafka-staging".command[2]' "$PROJECT/.opencode/kafka-staging.mcp.json"
  # Escaped, so the space cannot break the redirection and no metacharacter can
  # execute when the harness starts the server.
  assert_output --partial '.agents\ dir/logs'
}

@test "init: a connection that stops rendering is retired, not left registered" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  _project staging
  run _init
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]

  # The catalogue entry breaks: the manifest must go with the failure, or the
  # harness keeps a server whose launcher dies at launch.
  _catalogue '{"staging": {"bootstrap_server": "broker:9092"}}'
  _global
  run _init

  assert_success
  assert_output --partial "retired kafka-staging"
  assert [ ! -f "$PROJECT/.agents/mcp-runtime/kafka-staging.json" ]
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "init: a deselected connection is retired from the harness" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}, "production": {"bootstrap_servers": "prod:9092"}}'
  _global
  _project staging
  run _init
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]

  _project production
  run _init

  assert_success
  assert_output --partial "retired kafka-staging"
  assert [ ! -f "$PROJECT/.agents/mcp-runtime/kafka-staging.json" ]
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
  assert [ -f "$PROJECT/.opencode/kafka-production.mcp.json" ]
}

@test "init: a disabled module wires nothing and leaves no module memory" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global '{"kafka": false}'
  _project staging

  run _init

  assert_success
  assert_output --partial "module disabled for this project; nothing wired"
  # Not even the canonical manifest: the guard runs before anything is rendered
  # or published, so a direct call cannot wire a module the user turned off.
  assert [ ! -f "$PROJECT/.agents/mcp-runtime/kafka-staging.json" ]
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
  assert [ ! -f "$PROJECT/.agents/memory/active/modules/kafka.md" ]
}

@test "init: disabling the module retires what an earlier init wired" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  _project staging
  run _init
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]

  # Turning the module off must retire the server, not merely stop re-wiring it.
  _global '{"kafka": false}'
  run _init

  assert_success
  assert_output --partial "module disabled for this project; nothing wired"
  assert [ ! -f "$PROJECT/.agents/mcp-runtime/kafka-staging.json" ]
  assert [ ! -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "init: module memory is written only while a server is wired" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global

  _project staging
  run _init
  assert [ -f "$PROJECT/.agents/memory/active/modules/kafka.md" ]
  run cat "$PROJECT/.agents/memory/active/modules/kafka.md"
  assert_output --partial "kafka-<connection>"

  # Nothing selected: the rule would name a server that does not exist.
  _project
  run _init
  assert_success
  assert_output --partial "no connection wired"
  assert [ ! -f "$PROJECT/.agents/memory/active/modules/kafka.md" ]
}

# ── kafka-mcp-launch.sh ───────────────────────────────────────────────────────

@test "launcher: --which resolves the installed server, and fails without it" {
  run _launch --which
  assert_success

  rm -f "$BIN/mcp-confluent"
  run env DEV_BOT_ROOT="$SANDBOX" PATH="/usr/bin:/bin" bash "$LAUNCHER" --which
  assert_failure
  assert_output --partial "is not installed"
}

@test "launcher: the npm global prefix wins over a stale binary on PATH" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  # install.sh writes into npm's global prefix. A different binary earlier on
  # PATH must not be the one a launch runs, or the pin names a version that is
  # not in play.
  mkdir -p "$TMP/prefix/bin"
  printf '#!/usr/bin/env bash\necho "FROM-PREFIX"\n' >"$TMP/prefix/bin/mcp-confluent"
  chmod +x "$TMP/prefix/bin/mcp-confluent"
  cat >"$BIN/npm" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "prefix" && "${2:-}" == "-g" ]]; then
  printf '%s\n' "${PREFIX_ROOT}"
  exit 0
fi
exit 1
EOF
  chmod +x "$BIN/npm"

  run env PREFIX_ROOT="$TMP/prefix" DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_success
  assert_output --partial "FROM-PREFIX"
  refute_output --partial "ARGS:"
}

@test "launcher: execs the server with the allowlist, the config and DO_NOT_TRACK" {
  _catalogue "$_STAGING"
  _global

  MY_PASS=hunter2 run _launch staging

  assert_success
  # --transport is NOT passed: with --config the pair is a startup error.
  refute_output --partial "--transport"
  assert_output --partial "--config $(_published staging)"
  # The read surface, and none of the write tools.
  assert_output --partial "--allow-tools list-topics,get-partition-offsets"
  assert_output --partial "consume-messages"
  refute_output --partial "produce-message"
  refute_output --partial "delete-topics"
  # get-topic-config needs the Cloud REST fields, so it never registers here.
  refute_output --partial "get-topic-config"
  assert_output --partial "TRACK:1"
  # The credential reaches the server through the 0600 config only — never its
  # argv (readable through ps) and never its environment.
  assert_output --partial "PASS:<unset>"
  refute_output --partial "hunter2"
  run grep -c 'hunter2' "$(_published staging)"
  assert_output "1"
}

@test "launcher: an empty ordinary property is carried, an empty secret is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${SECRET}"}, "extra_properties": {"debug": "${EMPTY_VALUE}"}}}'
  _global
  printf 'SECRET=s3cret\nEMPTY_VALUE=\n' >"$SANDBOX/.env"

  run env -u EMPTY_VALUE -u SECRET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  # Present-but-empty is a value the server accepts, so it is carried…
  assert_success
  run grep -c 'debug: ""' "$(_published staging)"
  assert_output "1"

  # …while an empty credential is a configuration error, not a silent blank.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${EMPTY_VALUE}"}}}'
  _global
  run env -u EMPTY_VALUE DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging
  assert_failure
  assert_output --partial "must be a non-empty string"
}

@test "launcher: the repo dotenv is parsed, not inherited whole" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${MY_PASS}"}}}'
  _global
  # The file holds the connection's credential AND an unrelated one.
  printf 'MY_PASS=from-dotenv\nKAFKA_TEST_LEAK=unrelated-secret\n' >"$SANDBOX/.env"

  run env -u MY_PASS -u KAFKA_TEST_LEAK DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_success
  # Present in the file, needed by nobody: never reaches the third-party server.
  assert_output --partial "LEAK:<unset>"
  # Referenced through the env block: resolved from the file into the config.
  run grep -c 'from-dotenv' "$(_published staging)"
  assert_output "1"
}

@test "launcher: --check proves the installed server accepts the config" {
  # No credential references here: an unresolved value deliberately skips the
  # preflight (a reinit must not require the secret), and this test is about the
  # preflight itself running.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  : >"$TMP/seen-telemetry"

  run _launch --check staging

  assert_success
  assert_output --partial "connection 'staging' OK"
  # The preflight starts the real server, so it must carry the opt-out too.
  run cat "$TMP/seen-telemetry"
  assert_output "TRACK:1"
}

@test "launcher: --check surfaces the server's own rejection" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  _rejecting_server

  run _launch --check staging

  assert_failure
  assert_output --partial "rejected the rendered config"
  assert_output --partial "failed schema validation"
}

@test "launcher: a credential keeps its spaces, equals signs and inner quotes" {
  # The dotenv reader treats only a matching surrounding quote pair as syntax; a
  # secret that ends in a space or contains `=` must arrive unchanged.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${ODD}"}}}'
  _global
  printf 'ODD=  pa"ss==word  \n' >"$SANDBOX/.env"

  run env -u ODD DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$LAUNCHER" staging

  assert_success
  run grep -cF '  pa\"ss==word  ' "$(_published staging)"
  assert_output "1"
}

@test "launcher: a dot-directory name is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global

  run _launch --check ..

  assert_failure
  assert_output --partial "is not a valid connection name"
}

@test "launcher: a connection name that is a path is refused" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global

  run _launch --check ../outside

  assert_failure
  assert_output --partial "is not a valid connection name"
  # Nothing written outside the runtime directory either.
  assert [ ! -f "$TMP/outside.yaml" ]
  assert [ ! -f "$(dirname "$RUNTIME")/outside.yaml" ]
}

@test "launcher: an auth reference is supplied without an env block" {
  # The shipped example writes ${KAFKA_AUTH_VAR} in `auth` and nothing in `env`:
  # the launcher must still find it, or a copied config fails at startup.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "${KAFKA_AUTH_VAR}", "secret": "${KAFKA_AUTH_SECRET}"}}}'
  _global
  printf 'KAFKA_AUTH_VAR=resolved-from-dotenv\nKAFKA_AUTH_SECRET=s3cret\n' >"$SANDBOX/.env"

  run env -u KAFKA_AUTH_VAR -u KAFKA_AUTH_SECRET DEV_BOT_ROOT="$SANDBOX" \
    KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_success
  # Resolved into the config; the server's environment still holds nothing.
  run grep -c 'resolved-from-dotenv' "$(_published staging)"
  assert_output "1"
}

@test "launcher: an ambient secret never reaches the server" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global

  # Exported by the harness this time, not the dotenv: the child is scrubbed.
  run env KAFKA_TEST_LEAK=ambient-secret DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_success
  assert_output --partial "LEAK:<unset>"
}

@test "launcher: an env reference that resolves to nothing refuses the launch" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${KAFKA_DEFINITELY_UNSET}"}}}'
  _global

  run env -u KAFKA_DEFINITELY_UNSET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_failure
  assert_output --partial "'KAFKA_DEFINITELY_UNSET' is referenced in the config but resolves to nothing"
}

@test "launcher: the rendered config is private to the user" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global

  run _launch staging
  assert_success

  run bash -c "ls -l $(_published staging) | cut -c1-10"
  assert_output "-rw-------"
  run bash -c "ls -ld '$RUNTIME' | cut -c1-10"
  assert_output "drwx------"
}

@test "launcher: a credential cannot reshape the rendered YAML" {
  # The value is resolved as DATA and re-emitted through json.dumps, so a quote
  # or a colon cannot close the scalar — or add a key of its own.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${QUOTED}"}}}'
  _global
  printf 'QUOTED=pa"ss: x\nread_only: false\n' >"$SANDBOX/.env"

  run env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$LAUNCHER" staging

  assert_success
  run grep -c '\"ss: x' "$(_published staging)"
  assert_output "1"
  # The injected key never becomes a key: the newline stays inside the scalar.
  run grep -c '^read_only: false' "$(_published staging)"
  assert_output "0"
  run grep -c '^    read_only: true' "$(_published staging)"
  assert_output "1"
}

@test "launcher: different credentials publish different configs" {
  # A shared path would let a second launch swap the first one's credentials
  # between the render and the server's read.
  _catalogue "$_STAGING"
  _global

  MY_PASS=first run _launch staging
  assert_success
  first="$(_published staging)"
  MY_PASS=second run _launch staging
  assert_success

  run bash -c "ls -1 $RUNTIME/staging-*.yaml | wc -l"
  assert_output "2"
  run grep -c 'first' "$first"
  assert_output "1"
}

@test "launcher: bootstrap_servers references resolve too" {
  # The broker address is a reference like any other; the server's environment is
  # scrubbed, so leaving it unresolved means the connection cannot start.
  _catalogue '{"staging": {"bootstrap_servers": "${BROKER}"}}'
  _global
  printf 'BROKER=broker.from.dotenv:9092\n' >"$SANDBOX/.env"

  run env -u BROKER DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$LAUNCHER" staging

  assert_success
  run grep -c 'broker.from.dotenv:9092' "$(_published staging)"
  assert_output "1"
}

@test "launcher: the config name carries a collision-resistant digest" {
  _catalogue "$_STAGING"
  _global

  MY_PASS=hunter2 run _launch staging
  assert_success

  name="$(basename "$(_published staging)")"
  [[ "${name}" =~ ^staging-[0-9a-f]{16}\.yaml$ ]]
}

@test "launcher: a resolved config older than an hour is pruned" {
  _catalogue "$_STAGING"
  _global
  # A file left by a rotated credential: nothing is waiting on it any more.
  mkdir -p "$RUNTIME"
  printf 'old: "secret"\n' >"${RUNTIME}/staging-deadbeefdeadbeef.yaml"
  touch -t 202001010000 "${RUNTIME}/staging-deadbeefdeadbeef.yaml"

  MY_PASS=hunter2 run _launch staging

  assert_success
  assert [ ! -f "${RUNTIME}/staging-deadbeefdeadbeef.yaml" ]
  # The file this launch is using stays.
  assert [ -f "$(_published staging)" ]
}

@test "launcher: a reference missing outside env is lenient under --check" {
  # `devbot reinit` on a machine that does not hold the credential must still
  # wire the connection: the secret lives where the session runs, not here.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${ABSENT_SECRET}"}}}'
  _global
  _project staging

  run env -u ABSENT_SECRET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" --check staging

  assert_success
  assert_output --partial "ABSENT_SECRET"
  assert_output --partial "startup not checked"

  run _init
  assert_success
  assert [ -f "$PROJECT/.opencode/kafka-staging.mcp.json" ]
}

@test "launcher: the same missing reference is fatal on a launch" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${ABSENT_SECRET}"}}}'
  _global

  run env -u ABSENT_SECRET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_failure
  assert_output --partial "ABSENT_SECRET"
}

@test "launcher: a runtime directory that cannot be private is refused" {
  # A filesystem that ignores modes would leave the resolved credentials in a
  # shared directory; the guarantee is enforced, not assumed.
  mkdir -p "$RUNTIME"
  chmod 755 "$RUNTIME"

  run env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash -c "source '$MODULE_DIR/functions.sh'; _kafka_mode_private '$RUNTIME' && echo private || echo SHARED"

  assert_output "SHARED"
  chmod 700 "$RUNTIME"
  run env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash -c "source '$MODULE_DIR/functions.sh'; _kafka_mode_private '$RUNTIME' && echo private || echo SHARED"
  assert_output "private"
}

@test "launcher: a failed check publishes nothing" {
  # The document still holds `${VAR}` placeholders, so it is not a config — and
  # publishing it would leave this connection's other credentials on disk.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "agent", "secret": "${ABSENT_SECRET}"}}}'
  _global

  run env -u ABSENT_SECRET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" --check staging

  assert_success
  assert_output --partial "startup not checked"

  run env -u ABSENT_SECRET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_failure
  run bash -c "ls -1 '$RUNTIME' 2>/dev/null | grep -c 'staging-.*\\.yaml' || true"
  assert_output "0"
}

@test "launcher: --print-config keeps references unresolved" {
  _catalogue "$_STAGING"
  _global
  printf 'MY_PASS=very-secret\n' >"$SANDBOX/.env"

  run env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="$BIN:$PATH" \
    bash "$LAUNCHER" --print-config staging

  assert_success
  # This output gets read, pasted and logged; the value stays in the 0600 file.
  assert_line '        secret: "${MY_PASS}"'
  refute_output --partial "very-secret"
}

@test "launcher: --print-config masks a literal credential" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "literal-key", "secret": "${SECRET}"}}}'
  _global

  run _launch --print-config staging

  assert_success
  # A reference names the variable it needs — useful. A literal is a secret and
  # this output gets read, pasted and logged.
  assert_line '        key: "***"'
  assert_line '        secret: "${SECRET}"'
  refute_output --partial "literal-key"
}

@test "launcher: --print-config masks a credential in extra_properties" {
  # librdkafka carries SCRAM and TLS passwords here; the property NAME is
  # masked on the same rule as `auth`, and a reference stays visible.
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "extra_properties": {"security.protocol": "SASL_SSL", "sasl.username": "literal-user", "sasl.password": "${PASS}"}}}'
  _global

  run _launch --print-config staging

  assert_success
  assert_line '        security.protocol: "SASL_SSL"'
  assert_line '        sasl.username: "***"'
  assert_line '        sasl.password: "${PASS}"'
  refute_output --partial "literal-user"
}

@test "launcher: a failed launch leaves no temp file behind" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092", "auth": {"type": "api_key", "key": "k", "secret": "${NOPE_UNSET}"}}}'
  _global

  run env -u NOPE_UNSET DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" \
    PATH="$BIN:$PATH" bash "$LAUNCHER" staging

  assert_failure
  run bash -c "ls -a '$RUNTIME' 2>/dev/null | grep -cE '^\.(mapping|missing)' || true"
  assert_output "0"
}

@test "launcher: --print-config needs no installed server" {
  _catalogue '{"staging": {"bootstrap_servers": "broker:9092"}}'
  _global
  rm -f "$BIN/mcp-confluent"

  run env DEV_BOT_ROOT="$SANDBOX" KAFKA_RUNTIME_DIR="$RUNTIME" PATH="/usr/bin:/bin" \
    bash "$LAUNCHER" --print-config staging

  assert_success
  assert_line '      bootstrap_servers: "broker:9092"'
}

# ── the pin's allowlist arithmetic ────────────────────────────────────────────

@test "version floor: the package's own floor passes and one below fails" {
  run env DEV_BOT_ROOT="$SANDBOX" bash -c '
    source "$1/functions.sh"
    _kafka_version_ge 22.23.4 22.23.4 && echo floor-ok
    _kafka_version_ge 22.23.5 22.23.4 && echo above-ok
    _kafka_version_ge 23.0.0 22.23.4 && echo major-ok
    _kafka_version_ge 22.23.3 22.23.4 || echo below-rejected
    _kafka_version_ge 12.0.0 22.23.4 || echo ancient-rejected
  ' _ "$MODULE_DIR"

  assert_success
  assert_output --partial "floor-ok"
  assert_output --partial "above-ok"
  assert_output --partial "major-ok"
  assert_output --partial "below-rejected"
  assert_output --partial "ancient-rejected"
  refute_output --partial "below-ok"
}

@test "allowlist: a colourised listing still matches every name" {
  # 1.6.1 wraps the indent, name and colon in escapes; a regex anchored on the
  # plain shape would report EVERY tool missing and fail every update.
  run env DEV_BOT_ROOT="$SANDBOX" PATH="$BIN:$PATH" bash -c '
    source "$1/functions.sh"
    printf "now:[%s]\\n" "$(_kafka_missing_tools)"
  ' _ "$MODULE_DIR"
  assert_success
  assert_output "now:[]"
  # The probe runs from `devbot update`; it must not report telemetry either.
  run grep -c 'TRACK:1' "$TMP/seen-telemetry"
  assert_output "1"

  # An upgraded server that renamed get-consumer-group-lag must be caught, or
  # --allow-tools would drop it with a warning and the skill would promise a
  # tool the session cannot call.
  cat >"$BIN/mcp-confluent" <<'EOF'
#!/usr/bin/env bash
printf 'kafka:\n  list-topics: x\n  consume-messages: x\n'
EOF
  chmod +x "$BIN/mcp-confluent"
  run env DEV_BOT_ROOT="$SANDBOX" PATH="$BIN:$PATH" bash -c '
    source "$1/functions.sh"
    _kafka_missing_tools
  ' _ "$MODULE_DIR"

  assert_success
  assert_output --partial "get-consumer-group-lag"
  assert_output --partial "list-schemas"
}
