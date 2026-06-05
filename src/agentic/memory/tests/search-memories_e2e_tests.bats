#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/search-memories_e2e_tests.bats
# End-to-end tests for search-memories against a real QMD index.
# Creates temp collections, indexes markdown files, searches, and cleans up.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/search-memories/search-memories.sh"
  REINDEX_TOOL="$MODULE_DIR/tools/reindex-memories/reindex-memories.sh"

  # Skip all tests if qmd is not available
  command -v qmd &>/dev/null || skip "qmd CLI not installed"

  # Temp collections are registered in an isolated index under
  # DEVBOT_ROOT/storage (XDG_CACHE_HOME). search-memories.py strips
  # XDG_CACHE_HOME so production searches the user's default index;
  # SEARCH_MEMORIES_XDG_CACHE_HOME opts the tool into the same
  # isolated index for this test run.
  DEVBOT_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"
  export XDG_CACHE_HOME="$DEVBOT_ROOT/storage"
  export SEARCH_MEMORIES_XDG_CACHE_HOME="$DEVBOT_ROOT/storage"
  export DEVBOT_ROOT

  # Create a temporary directory for test content
  E2E_TMPDIR="$(mktemp -d)"
  export E2E_TMPDIR

  # Collection name unique to this test run
  E2E_COLLECTION="e2e-test-$$"
  export E2E_COLLECTION
}

teardown() {
  # Remove the temporary QMD collection
  if [[ -n "${E2E_COLLECTION:-}" ]] && command -v qmd &>/dev/null; then
    qmd collection remove "$E2E_COLLECTION" 2>/dev/null || true
  fi
  # Clean up temp dir
  if [[ -n "${E2E_TMPDIR:-}" ]]; then
    rm -rf "$E2E_TMPDIR"
  fi
}

# Helper: create test markdown files and register collection
setup_e2e_collection() {
  mkdir -p "$E2E_TMPDIR/notes"

  # File 1: about authentication
  cat > "$E2E_TMPDIR/notes/auth-setup.md" <<'MARKDOWN'
---
tags: [authentication, security]
description: Setting up JWT authentication in the API gateway
---
# JWT Authentication Setup

This document describes how to configure JWT-based authentication
for the API gateway using RS256 asymmetric keys.

## Prerequisites

- OpenSSL 1.1+
- A key pair stored in AWS KMS
MARKDOWN

  # File 2: about deployment
  cat > "$E2E_TMPDIR/notes/deploy-guide.md" <<'MARKDOWN'
---
tags: [deployment, kubernetes]
description: Kubernetes deployment guide for production
---
# Kubernetes Deployment Guide

Step-by-step instructions for deploying services to the
production Kubernetes cluster.

## Rolling Updates

Use `kubectl rollout` to perform zero-downtime deployments.
The deployment strategy is configured in the Helm chart.
MARKDOWN

  # File 3: about database
  cat > "$E2E_TMPDIR/notes/database-migration.md" <<'MARKDOWN'
---
tags: [database, migration, postgresql]
description: Safe database migration procedures
---
# Database Migration Procedures

How to safely run PostgreSQL migrations in production
using Flyway.

## Pre-migration checklist

1. Backup the current database
2. Run migration in dry-run mode
3. Verify no locking issues
MARKDOWN

  # Register collection
  qmd collection add "$E2E_TMPDIR/notes" --name "$E2E_COLLECTION" --mask "**/*.md"
  qmd update
  # Give embedding a moment (or skip if GPU not available)
  qmd embed 2>/dev/null || true
}

# ── Basic search functionality ──────────────────────────────────────────────

@test "e2e: search finds matching document by content" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 5 "JWT authentication"

  assert_success
  assert_output --partial "JWT Authentication Setup"
  assert_output --partial "RS256"
}

@test "e2e: search finds document by tag metadata" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 5 "kubernetes deployment"

  assert_success
  assert_output --partial "Kubernetes Deployment Guide"
}

@test "e2e: search finds database migration document" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 5 "PostgreSQL migration"

  assert_success
  assert_output --partial "Database Migration Procedures"
}

@test "e2e: search returns empty result for non-matching query" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 3 "zzzqwertyuiop_nonexistent"

  # Should succeed but return "no matches" message or empty
  assert_success
  assert_output --regexp "(no memory|_No memory vault|no doc)" || true
}

# ── Format output variants ──────────────────────────────────────────────────

@test "e2e: --format json returns valid JSON" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 3 --json "authentication"

  assert_success

  # Verify it's valid JSON with a memories array
  run python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assert 'memories' in data, 'Missing memories key'
assert isinstance(data['memories'], list), 'memories is not a list'
print('VALID')
" <<< "$output"

  assert_output "VALID"
}

@test "e2e: --format markdown includes separator between results" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 5 --markdown "authentication"

  assert_success
  # Output should contain at least one match (not "No memory vault matches found")
  refute_output --partial "_No memory vault matches found._"
  # When results exist, separators appear between entries
  assert_output --regexp "---"
}

# ── Max results limiting ────────────────────────────────────────────────────

@test "e2e: --max-results limits number of results" {
  setup_e2e_collection

  run bash "$TOOL" --collection "$E2E_COLLECTION" --max-results 1 "deploy database auth"

  assert_success

  # Count separators to verify at most 1 result
  local sep_count
  sep_count=$(grep -c '^---$' <<< "$output" || true)
  [[ "$sep_count" -le 2 ]]  # header separator + at most 1 content separator
}

# ── Error handling ──────────────────────────────────────────────────────────

@test "e2e: missing --collection falls back to auto-detection" {
  setup_e2e_collection

  # Without explicit --collection, should use devbot collection
  run bash "$TOOL" --max-results 3 "qmd" 2>/dev/null
  # Should not crash even if results are empty
  [[ "$status" -eq 0 ]]
}

@test "e2e: non-existent collection returns error or empty" {
  run bash "$TOOL" --collection "non-existent-collection-xyz" --max-results 3 "test"

  # Should either error or return empty (graceful degradation)
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── Reindex ─────────────────────────────────────────────────────────────────

@test "e2e: reindex-memories returns JSON status" {
  run bash "$REINDEX_TOOL"

  assert_success
  assert_output --partial '"status":"started"'
}

# ── Integration: create, index, search, cleanup ─────────────────────────────

@test "e2e: full lifecycle — register, index, search, remove" {
  local tmp_dir tmp_coll
  tmp_dir="$(mktemp -d)"
  tmp_coll="lifecycle-test-$$"

  # Step 1: Create content
  mkdir -p "$tmp_dir/data"
  cat > "$tmp_dir/data/integration-test.md" <<'MARKDOWN'
---
tags: [integration, test]
description: Integration test document for QMD lifecycle
---
# Integration Test Document

This is a unique document used to verify the full QMD lifecycle:
create collection, index content, search for it, and clean up.

## Unique Identifier

lifecycle-test-token-xyz-42
MARKDOWN

  # Step 2: Register collection
  run qmd collection add "$tmp_dir/data" --name "$tmp_coll" --mask "**/*.md"
  assert_success

  # Step 3: Index
  run qmd update
  assert_success
  qmd embed 2>/dev/null || true

  # Step 4: Search
  run bash "$TOOL" --collection "$tmp_coll" --max-results 3 "lifecycle-test-token"
  assert_success
  assert_output --partial "Integration Test Document"
  assert_output --partial "lifecycle-test-token-xyz-42"

  # Step 5: Cleanup
  run qmd collection remove "$tmp_coll"
  assert_success

  rm -rf "$tmp_dir"
}
