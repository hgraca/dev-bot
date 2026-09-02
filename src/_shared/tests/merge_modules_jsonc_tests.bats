#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/merge_modules_jsonc_tests.bats
# Tests for merge_modules_jsonc.py — insert / --remove / --update modes of the
# comment-preserving editor for the external_modules config section.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TOOL="${TEST_DIR}/../merge_modules_jsonc.py"
  WORK="$(mktemp -d)"

  cat > "${WORK}/cfg.jsonc" <<'EOF'
{
  // top-level comment must survive
  "gpu_enabled": true,
  "external_modules": {
    "addyosmani": { "url": "https://github.com/addyosmani/agent-skills.git", "paths": { "skills": "skills" } },
    "local-thing": { "path": "/tmp/local", "paths": { "skills": "skills" } }
  }
}
EOF
}

teardown() {
  rm -rf "${WORK}" 2>/dev/null || true
}

_assert_parses() {
  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
load_jsonc('${WORK}/cfg.jsonc')
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: adds missing entry and reports INSERTED" {
  cat > "${WORK}/decl.json" <<'EOF'
{"mattpocock-grilling": {"url": "https://github.com/mattpocock/skills.git", "paths": {"skills": "skills/productivity/grilling"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
assert 'mattpocock-grilling' in d['external_modules'], d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: existing entry is skipped (SKIP_ALL)" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "SKIP_ALL"
}

@test "remove: removes entry and reports REMOVED" {
  run python3 "$TOOL" "${WORK}/cfg.jsonc" --remove local-thing

  assert_success
  assert_output --partial "REMOVED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
assert 'local-thing' not in d['external_modules'], d
assert 'addyosmani' in d['external_modules'], d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "remove: unknown key reports NOT_FOUND and leaves file unchanged" {
  cp "${WORK}/cfg.jsonc" "${WORK}/before.jsonc"

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --remove nope

  assert_success
  assert_output --partial "NOT_FOUND"
  assert [ "$(cat "${WORK}/before.jsonc")" = "$(cat "${WORK}/cfg.jsonc")" ]
}

@test "remove/update: comments outside external_modules survive" {
  run python3 "$TOOL" "${WORK}/cfg.jsonc" --remove local-thing
  assert_success

  run grep -c "top-level comment must survive" "${WORK}/cfg.jsonc"
  assert_success
  assert_output "1"
}

@test "update: merges declaration url/paths and preserves user-added path" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {"agents": "agents", "skills": "skills"}}}
EOF
  # Give addyosmani a user-added local path override to prove preservation.
  run python3 -c "
import sys, json
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
d['external_modules']['addyosmani']['path'] = '/tmp/override'
with open('${WORK}/cfg.jsonc', 'w') as f:
    json.dump(d, f, indent=2)
"
  assert_success

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json"
  assert_success
  assert_output --partial "UPDATED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['addyosmani']
assert entry['url'] == 'https://github.com/addyosmani/agent-skills.git', entry
assert entry['paths'] == {'agents': 'agents', 'skills': 'skills'}, entry
assert entry['path'] == '/tmp/override', entry  # user override preserved
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: with --owner records _declared_by, not _user_added" {
  cat > "${WORK}/decl.json" <<'EOF'
{"new-mod": {"url": "https://example.com/acme/new.git", "paths": {"skills": "skills"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json" --owner some-module

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['new-mod']
assert entry['_declared_by'] == ['some-module'], entry
assert '_user_added' not in entry, entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: without --owner records _user_added" {
  cat > "${WORK}/decl.json" <<'EOF'
{"user-mod": {"path": "/tmp/foo", "paths": {"skills": "skills"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['user-mod']
assert entry.get('_user_added') is True, entry
assert '_declared_by' not in entry, entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "update: with --owner unions _declared_by across declarers" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {"skills": "skills"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json" --owner mod-a
  assert_success
  assert_output --partial "UPDATED"
  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json" --owner mod-b
  assert_success
  assert_output --partial "UPDATED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['addyosmani']
assert entry['_declared_by'] == ['mod-a', 'mod-b'], entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "remove: finds section when external_modules is first key after a comment" {
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  // a comment before the section
  "external_modules": {
    "only-one": { "url": "https://example.com/x.git", "paths": {} }
  }
}
EOF

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" --remove only-one

  assert_success
  assert_output --partial "REMOVED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg2.jsonc')
assert 'external_modules' in d and d['external_modules'] == {}, d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "remove: config-only entries not in declaration are untouched" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {"skills": "skills"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json"
  assert_success
  assert_output --partial "UPDATED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
assert d['external_modules']['local-thing'] == {'path': '/tmp/local', 'paths': {'skills': 'skills'}}, d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "update: unknown keys are skipped (SKIP_ALL)" {
  cat > "${WORK}/decl.json" <<'EOF'
{"ghost": {"url": "https://example.com/ghost.git", "paths": {}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json"

  assert_success
  assert_output --partial "SKIP_ALL"
}

@test "insert: array path value round-trips with element order preserved" {
  cat > "${WORK}/decl.json" <<'EOF'
{"mindrally/skills": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": ["skills/react", "skills/nextjs-react-typescript"]}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['mindrally/skills']
assert entry['paths']['skills'] == ['skills/react', 'skills/nextjs-react-typescript'], entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: string, array and memory-dict path forms coexist in one entry" {
  cat > "${WORK}/decl.json" <<'EOF'
{"mindrally/skills": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": ["skills/react", "skills/nextjs-react-typescript"], "agents": "agents", "memory": {"CLAUDE.md": "bootstrap/CLAUDE.md"}}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['mindrally/skills']
assert entry['paths']['skills'] == ['skills/react', 'skills/nextjs-react-typescript'], entry
assert entry['paths']['agents'] == 'agents', entry
assert entry['paths']['memory'] == {'CLAUDE.md': 'bootstrap/CLAUDE.md'}, entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "update: declaration array paths replace existing string paths" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {"skills": ["skills/one", "skills/two"]}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json"

  assert_success
  assert_output --partial "UPDATED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
entry = d['external_modules']['addyosmani']
assert entry['paths']['skills'] == ['skills/one', 'skills/two'], entry
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "update: entries untouched by the update keep legacy string paths verbatim" {
  cat > "${WORK}/decl.json" <<'EOF'
{"addyosmani": {"url": "https://github.com/addyosmani/agent-skills.git", "paths": {"skills": ["skills/one"]}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg.jsonc" --update "${WORK}/decl.json"

  assert_success
  assert_output --partial "UPDATED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg.jsonc')
assert d['external_modules']['local-thing'] == {'path': '/tmp/local', 'paths': {'skills': 'skills'}}, d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "insert: refuses short key when repo already declared under another key" {
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  "external_modules": {
    "mindrally/skills": { "url": "https://github.com/mindrally/skills.git", "paths": { "skills": ["skills/react"] } }
  }
}
EOF
  cat > "${WORK}/decl.json" <<'EOF'
{"mindrally-skills": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": "skills/react"}}}
EOF
  cp "${WORK}/cfg2.jsonc" "${WORK}/before.jsonc"

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" "${WORK}/decl.json"

  assert_failure
  assert_output --partial "already declared as 'mindrally/skills'"
  assert [ "$(cat "${WORK}/before.jsonc")" = "$(cat "${WORK}/cfg2.jsonc")" ]
}

@test "insert: canonical key (key == derived org/repo) is not refused" {
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  "external_modules": {}
}
EOF
  cat > "${WORK}/decl.json" <<'EOF'
{"mindrally/skills": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": ["skills/react", "skills/nextjs-react-typescript"]}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"

  run python3 -c "
import sys
sys.path.insert(0, '${TEST_DIR}/..')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/cfg2.jsonc')
assert d['external_modules']['mindrally/skills']['paths']['skills'] == ['skills/react', 'skills/nextjs-react-typescript'], d
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "update: refuses updating an entry whose repo is held by a different key" {
  # Pre-guard legacy state: a canonical entry and a differently-keyed twin on
  # the same repo url. Updating the twin must be refused.
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  "external_modules": {
    "mindrally/skills": { "url": "https://github.com/mindrally/skills.git", "paths": { "skills": ["skills/react"] }, "_declared_by": ["react"] },
    "mindrally-skills": { "url": "https://github.com/mindrally/skills.git", "paths": { "skills": "skills/svelte" }, "_declared_by": ["svelte"] }
  }
}
EOF
  cat > "${WORK}/decl.json" <<'EOF'
{"mindrally-skills": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": "skills/other"}}}
EOF
  cp "${WORK}/cfg2.jsonc" "${WORK}/before.jsonc"

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" --update "${WORK}/decl.json"

  assert_failure
  assert_output --partial "already declared as 'mindrally/skills'"
  assert [ "$(cat "${WORK}/before.jsonc")" = "$(cat "${WORK}/cfg2.jsonc")" ]
}

@test "insert: two differently-keyed declarations for one repo in a batch are refused atomically" {
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  "external_modules": {}
}
EOF
  cat > "${WORK}/decl.json" <<'EOF'
{"react-one": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": "skills/react"}}, "react-two": {"url": "https://github.com/mindrally/skills.git", "paths": {"skills": "skills/svelte"}}}
EOF
  cp "${WORK}/cfg2.jsonc" "${WORK}/before.jsonc"

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" "${WORK}/decl.json"

  assert_failure
  assert_output --partial "already declared as 'react-one'"
  assert [ "$(cat "${WORK}/before.jsonc")" = "$(cat "${WORK}/cfg2.jsonc")" ]
}

@test "insert: local-path declaration without url never collides" {
  cat > "${WORK}/cfg2.jsonc" <<'EOF'
{
  "external_modules": {
    "mindrally/skills": { "path": "/tmp/local", "paths": { "skills": "skills" } }
  }
}
EOF
  cat > "${WORK}/decl.json" <<'EOF'
{"other/local": {"path": "/tmp/other", "paths": {"skills": "skills"}}}
EOF

  run python3 "$TOOL" "${WORK}/cfg2.jsonc" "${WORK}/decl.json"

  assert_success
  assert_output --partial "INSERTED"
}
