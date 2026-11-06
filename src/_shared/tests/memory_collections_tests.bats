#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/memory_collections_tests.bats
# Tests for the memory_collections config resolver.
#
# Hermetic: DEV_BOT_ROOT points at a sandbox holding a fixture global config,
# and each project lives in its own temp dir. No machine config is consulted.
#
# Run from project root:
#   bats src/_shared/tests/memory_collections_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"
  PROJECT_DIR="$(mktemp -d)"
  RESOLVER="${PROJECT_ROOT}/src/_shared/memory_collections.py"

  command -v python3 &>/dev/null || skip "python3 not installed"

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" "${PROJECT_DIR}" 2>/dev/null || true
}

# ── Fixture helpers ──────────────────────────────────────────────────────────

_write_global_cfg() {
  printf '%s\n' "$1" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

_write_project_cfg() {
  printf '%s\n' "$1" > "${PROJECT_DIR}/.devbot.project.jsonc"
}

resolve() {
  run python3 "${RESOLVER}" --project-root "${PROJECT_DIR}"
}

# Read one field of one resolved collection from the last `resolve` output.
field() {
  printf '%s' "${output}" | python3 -c '
import json, sys
entry = next(c for c in json.load(sys.stdin)["collections"] if c["key"] == sys.argv[1])
value = entry[sys.argv[2]]
print(json.dumps(value) if isinstance(value, bool) else value)
' "$1" "$2"
}

keys() {
  printf '%s' "${output}" | python3 -c '
import json, sys
print(",".join(c["key"] for c in json.load(sys.stdin)["collections"]))
'
}

# ── Defaults ─────────────────────────────────────────────────────────────────

@test "defaults: project and global collections are always present" {
  resolve
  assert_success
  assert_equal "$(keys)" "project,global"
  assert_equal "$(field project path)" "${PROJECT_DIR}/.agents/memory/latent"
  assert_equal "$(field project physical)" "$(basename "${PROJECT_DIR}")"
  assert_equal "$(field project kind)" "project"
  assert_equal "$(field global path)" "${SANDBOX_DIR}/storage/global-memories"
  assert_equal "$(field global physical)" "dev-bot-global"
}

@test "defaults: the project collection follows devbot_dir" {
  _write_project_cfg '{ "devbot_dir": ".custom-agents" }'

  resolve
  assert_success
  assert_equal "$(field project path)" "${PROJECT_DIR}/.custom-agents/memory/latent"
}

@test "defaults: the physical project name follows project_name" {
  _write_project_cfg '{ "project_name": "renamed" }'

  resolve
  assert_success
  assert_equal "$(field project physical)" "renamed"
}

# ── Custom collections and precedence ────────────────────────────────────────

@test "custom: a global entry resolves with a namespaced physical name" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "~/notes", "semantic": true } }
  }'

  resolve
  assert_success
  assert_equal "$(field notes path)" "${HOME}/notes"
  [[ "$(field notes physical)" == dev-bot-custom-* ]] \
    || fail "physical not corpus-scoped: $(field notes physical)"
  assert_equal "$(field notes kind)" "custom"
  assert_equal "$(field notes source)" "global"
  assert_equal "$(field notes semantic)" "true"
}

@test "custom: a project key replaces the global entry wholesale" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "/global/notes", "semantic": false } }
  }'
  _write_project_cfg '{
    "memory_collections": { "notes": { "path": "/project/notes", "semantic": true } }
  }'

  resolve
  assert_success
  assert_equal "$(field notes path)" "/project/notes"
  assert_equal "$(field notes semantic)" "true"
  assert_equal "$(field notes source)" "project"
}

@test "custom: global and project keys merge" {
  _write_global_cfg '{
    "memory_collections": { "shared": { "path": "/shared" } }
  }'
  _write_project_cfg '{
    "memory_collections": { "local": { "path": "/local" } }
  }'

  resolve
  assert_success
  assert_equal "$(keys)" "project,global,local,shared"
}

@test "custom: semantic defaults to false" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "/notes" } }
  }'

  resolve
  assert_success
  assert_equal "$(field notes semantic)" "false"
}

# ── Reserved keys ────────────────────────────────────────────────────────────

@test "reserved: project in the global config is an error" {
  _write_global_cfg '{
    "memory_collections": { "project": { "path": "/x" } }
  }'

  resolve
  assert_failure
  assert_output --partial "may only be set in the project config"
}

@test "reserved: global in the project config is an error" {
  _write_project_cfg '{
    "memory_collections": { "global": { "path": "/x" } }
  }'

  resolve
  assert_failure
  assert_output --partial "may only be set in the global config"
}

# ── Validation ───────────────────────────────────────────────────────────────

@test "validation: a collection without a path is rejected" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "semantic": true } }
  }'

  resolve
  assert_failure
  assert_output --partial "needs a non-empty path"
}

@test "validation: a non-boolean semantic is rejected" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "/notes", "semantic": "yes" } }
  }'

  resolve
  assert_failure
  assert_output --partial "semantic must be true or false"
}

@test "validation: an unknown collection key is rejected" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "/notes", "weight": 2 } }
  }'

  resolve
  assert_failure
  assert_output --partial "unknown key(s): weight"
}

# ── Placeholders and ordering ────────────────────────────────────────────────

@test "placeholders: DEV_BOT_ROOT, project and relative paths resolve" {
  _write_global_cfg '{
    "memory_collections": {
      "a": { "path": "${DEV_BOT_ROOT}/docs" },
      "b": { "path": "{project}/docs" },
      "c": { "path": "relative/docs" }
    }
  }'

  resolve
  assert_success
  assert_equal "$(field a path)" "${SANDBOX_DIR}/docs"
  assert_equal "$(field b path)" "${PROJECT_DIR}/docs"
  assert_equal "$(field c path)" "${PROJECT_DIR}/relative/docs"
}

@test "ordering: project, global, then custom keys sorted" {
  _write_global_cfg '{
    "memory_collections": {
      "zeta": { "path": "/z" },
      "alpha": { "path": "/a" }
    }
  }'

  resolve
  assert_success
  assert_equal "$(keys)" "project,global,alpha,zeta"
}

@test "exists: reports whether the collection path is a directory" {
  mkdir -p "${PROJECT_DIR}/docs"
  _write_global_cfg '{
    "memory_collections": { "docs": { "path": "{project}/docs" } }
  }'

  resolve
  assert_success
  assert_equal "$(field docs exists)" "true"
}

@test "defaults: the built-in index paths are reported" {
  resolve
  assert_success
  assert_equal "$(field project index)" "${PROJECT_DIR}/.mdctx/context-index.json"
  assert_equal "$(field global index)" "${SANDBOX_DIR}/storage/.mdctx/context-index.json"
}

@test "custom: a key carries a corpus-path identity" {
  _write_project_cfg '{
    "project_name": "proj",
    "memory_collections": { "notes": { "path": "/n" } }
  }'

  resolve
  assert_success
  [[ "$(field notes physical)" == dev-bot-custom-* ]] \
    || fail "physical not corpus-scoped: $(field notes physical)"
  [[ "$(field notes index)" == "${SANDBOX_DIR}/storage/.mdctx/collections/"* ]] \
    || fail "index not corpus-scoped: $(field notes index)"
}

@test "custom: an absolute path is shared across projects" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "/shared/notes" } }
  }'

  resolve
  assert_success
  local first_physical="$(field notes physical)"
  local first_index="$(field notes index)"
  local second="$SANDBOX_DIR/other-project"
  mkdir -p "$second"

  run python3 "${RESOLVER}" --project-root "$second"
  assert_success
  assert_equal "$(field notes physical)" "$first_physical"
  assert_equal "$(field notes index)" "$first_index"
}

@test "custom: a project-relative path is scoped per project" {
  _write_global_cfg '{
    "memory_collections": { "notes": { "path": "{project}/docs" } }
  }'

  resolve
  assert_success
  local first_physical="$(field notes physical)"
  local second="$SANDBOX_DIR/other-project"
  mkdir -p "$second"

  run python3 "${RESOLVER}" --project-root "$second"
  assert_success
  assert_not_equal "$(field notes physical)" "$first_physical"
}

@test "custom: two keys for the same path share one registration" {
  _write_global_cfg '{
    "memory_collections": {
      "a": { "path": "/one" },
      "b": { "path": "/one" }
    }
  }'

  resolve
  assert_success
  assert_equal "$(field a physical)" "$(field b physical)"
  assert_equal "$(field a index)" "$(field b index)"
}

@test "custom: two keys for different paths get distinct identities" {
  _write_global_cfg '{
    "memory_collections": {
      "a": { "path": "/one" },
      "b": { "path": "/two" }
    }
  }'

  resolve
  assert_success
  assert_not_equal "$(field a physical)" "$(field b physical)"
  assert_not_equal "$(field a index)" "$(field b index)"
}

@test "validation: a collection name with a slash is rejected" {
  _write_global_cfg '{
    "memory_collections": { "bad/name": { "path": "/n" } }
  }'

  resolve
  assert_failure
  assert_output --partial "may only contain"
}

@test "validation: a project-dependent global path is rejected" {
  _write_global_cfg '{
    "memory_collections": { "global": { "path": "{project}/shared" } }
  }'

  resolve
  assert_failure
  assert_output --partial "must be machine-wide"
}

@test "validation: a relative global path is rejected" {
  _write_global_cfg '{
    "memory_collections": { "global": { "path": "shared" } }
  }'

  resolve
  assert_failure
  assert_output --partial "must be machine-wide"
}

@test "config: DEV_BOT_GLOBAL_CONFIG is honored" {
  local alt="$SANDBOX_DIR/alt-global.jsonc"
  printf '{ "memory_collections": { "global": { "path": "%s/alt-global" } } }\n' \
    "$SANDBOX_DIR" > "$alt"

  DEV_BOT_GLOBAL_CONFIG="$alt" run python3 "${RESOLVER}" --project-root "${PROJECT_DIR}"
  assert_success
  assert_equal "$(field global path)" "$SANDBOX_DIR/alt-global"
}

@test "custom: an alias of the global root reuses its identity" {
  _write_global_cfg '{
    "memory_collections": {
      "alias": { "path": "${DEV_BOT_ROOT}/storage/global-memories" }
    }
  }'

  resolve
  assert_success
  assert_equal "$(field alias physical)" "dev-bot-global"
  assert_equal "$(field alias index)" "$(field global index)"
}

@test "custom: an alias of the project root reuses its identity" {
  _write_project_cfg '{
    "project_name": "proj",
    "memory_collections": { "alias": { "path": "{project}/.agents/memory/latent" } }
  }'

  resolve
  assert_success
  assert_equal "$(field alias physical)" "proj"
  assert_equal "$(field alias index)" "$(field project index)"
}

@test "global: an overridden store gets a separate mdctx index" {
  _write_global_cfg '{
    "memory_collections": { "global": { "path": "/custom/global" } }
  }'

  resolve
  assert_success
  assert_equal "$(field global path)" "/custom/global"
  [[ "$(field global index)" == "${SANDBOX_DIR}/storage/.mdctx/collections/"* ]] \
    || fail "override does not get an isolated index: $(field global index)"
}

@test "custom: an alias of another registered project's vault is rejected" {
  local project_a="$SANDBOX_DIR/project-a" project_b="$SANDBOX_DIR/project-b"
  mkdir -p "$project_a/.agents/memory/latent" "$project_b/.agents/memory/latent"
  printf '{ "project_name": "a" }\n' > "$project_a/.devbot.project.jsonc"
  printf '{ "project_name": "b" }\n' > "$project_b/.devbot.project.jsonc"
  _write_global_cfg "{
    \"projects\": [\"$project_a\", \"$project_b\"],
    \"memory_collections\": { \"notes\": { \"path\": \"$project_a/.agents/memory/latent\" } }
  }"

  run python3 "${RESOLVER}" --project-root "$project_b"
  assert_failure
  assert_output --partial "cannot alias another checkout"
}

@test "custom: an alias of a sibling's overridden project path is rejected" {
  local project_a="$SANDBOX_DIR/project-a" project_b="$SANDBOX_DIR/project-b"
  local shared="$SANDBOX_DIR/shared-vault"
  mkdir -p "$project_a/.agents/memory/latent" "$project_b/.agents/memory/latent" "$shared"
  printf '{ "project_name": "a", "memory_collections": { "project": { "path": "%s" } } }\n' \
    "$shared" > "$project_a/.devbot.project.jsonc"
  printf '{ "project_name": "b" }\n' > "$project_b/.devbot.project.jsonc"
  _write_global_cfg "{
    \"projects\": [\"$project_a\", \"$project_b\"],
    \"memory_collections\": { \"notes\": { \"path\": \"$shared\" } }
  }"

  run python3 "${RESOLVER}" --project-root "$project_b"
  assert_failure
  assert_output --partial "cannot alias another checkout"
}

@test "custom: a symlink alias of another project's vault is rejected" {
  local project_a="$SANDBOX_DIR/project-a" project_b="$SANDBOX_DIR/project-b"
  local alias_a="$SANDBOX_DIR/alias-a"
  mkdir -p "$project_a/.agents/memory/latent" "$project_b/.agents/memory/latent"
  ln -s "$project_a/.agents/memory/latent" "$alias_a"
  printf '{ "project_name": "a" }\n' > "$project_a/.devbot.project.jsonc"
  printf '{ "project_name": "b" }\n' > "$project_b/.devbot.project.jsonc"
  _write_global_cfg "{
    \"projects\": [\"$project_a\", \"$project_b\"],
    \"memory_collections\": { \"notes\": { \"path\": \"$alias_a\" } }
  }"

  run python3 "${RESOLVER}" --project-root "$project_b"
  assert_failure
  assert_output --partial "cannot alias another checkout"
}

@test "custom: a symlink to a shared corpus reuses its identity" {
  local shared="$SANDBOX_DIR/shared" alias="$SANDBOX_DIR/shared-alias"
  mkdir -p "$shared"
  ln -s "$shared" "$alias"
  _write_global_cfg "{
    \"memory_collections\": {
      \"a\": { \"path\": \"$shared\" },
      \"b\": { \"path\": \"$alias\" }
    }
  }"

  resolve
  assert_success
  assert_equal "$(field a physical)" "$(field b physical)"
  assert_equal "$(field a index)" "$(field b index)"
}
