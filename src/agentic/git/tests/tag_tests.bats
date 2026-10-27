#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/tag_tests.bats
# Tests for the git tag helper (tools/tag.sh) — the git half of the release
# tooling. The sandbox lives in release_test_helper.bash.
# =============================================================================

load 'release_test_helper'

setup() {
  release_test_setup
  SCRIPT="$MODULE_DIR/tools/tag.sh"
}

# ── version: derived from the remote ─────────────────────────────────────────

@test "version: no argument bumps the remote's newest tag to the next minor" {
  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: a patch release on the remote still yields the next minor" {
  git -C "$WORK" tag 1.4.1
  git -C "$WORK" push -q origin 1.4.1

  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: an annotated tag is not misread as its peeled ^{} ref" {
  git -C "$WORK" tag -a 1.5.0 -m "annotated"
  git -C "$WORK" push -q origin 1.5.0

  release version

  assert_success
  assert_output "1.6.0"
}

@test "version: a remote with no tags refuses to guess" {
  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: a non-version tag newer than the release is ignored" {
  git -C "$WORK" tag nightly
  git -C "$WORK" push -q origin nightly

  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: a remote carrying only non-version tags refuses to guess" {
  git -C "$WORK" tag nightly
  git -C "$WORK" push -q empty main nightly

  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: a four-part remote tag bumps the third component" {
  git -C "$WORK" tag 0.7.4.0
  git -C "$WORK" push -q empty main refs/tags/0.7.4.0

  release version --remote empty

  assert_success
  assert_output "0.7.5.0"
}

@test "version: the unstable major-zero prefix shifts the bump to the third component" {
  git -C "$WORK" tag 0.1.2.3
  git -C "$WORK" push -q empty main refs/tags/0.1.2.3

  release version --remote empty

  assert_success
  assert_output "0.1.3.0"
}

@test "version: a three-part major-zero tag is not a version tag" {
  git -C "$WORK" tag 0.7.5
  git -C "$WORK" push -q empty main refs/tags/0.7.5

  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

# ── version: explicit argument ───────────────────────────────────────────────

@test "version: accepts a full semver argument" {
  release version --version 1.6.0

  assert_success
  assert_output "1.6.0"
}

@test "version: normalises a two-part argument to three parts" {
  release version --version 1.6

  assert_success
  assert_output "1.6.0"
}

@test "version: rejects a non-numeric argument" {
  release version --version abc

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a single-component argument" {
  release version --version 1

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a four-component argument when the major is non-zero" {
  release version --version 1.2.3.4

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: accepts a four-component argument when the major is zero" {
  release version --version 0.1.2.3

  assert_success
  assert_output "0.1.2.3"
}

@test "version: rejects a two-component argument when the major is zero" {
  release version --version 0.7

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a three-component argument when the major is zero" {
  release version --version 0.7.5

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a five-component argument" {
  release version --version 0.1.2.3.4

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a version that already exists on the remote" {
  release version --version 1.4.0

  assert_failure
  assert_output --partial "FATAL:"
}

# ── plan: the tag approval preview ───────────────────────────────────────────

@test "plan: names the version, tag and the branch it merges from and to" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '1.5.0'
  assert_output --partial 'feature/v1.5'
  assert_output --partial 'main'
}

@test "plan: reproduces the notes verbatim, heading included" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '# Release v1.5.0'
  assert_output --partial 'Removed model downloads, embedding and MCP from QMD.'
}

@test "plan: lists the remotes the tag and branch will be pushed to" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'origin'
  assert_output --partial 'second'
}

# ── plan: mutates nothing ────────────────────────────────────────────────────

@test "plan: takes the default branch from origin/HEAD when it is set" {
  git -C "$WORK" branch develop main
  git -C "$WORK" push -q origin develop
  git -C "$WORK" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  # Resolved by reading the symref, not by re-deriving it from the remote —
  # a `set-head --auto` would answer `main` here.
  assert_output --partial 'Default branch:** `develop`'
}

@test "plan: leaves the repository exactly as it found it" {
  local head_before status_before tags_before refs_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"
  status_before="$(git -C "$WORK" status --porcelain)"
  tags_before="$(git -C "$WORK" tag | sort | tr '\n' ' ')"
  # Every ref, including the remote-tracking ones: plan resolves the default
  # branch, and doing that by refreshing origin/HEAD would write this ref.
  refs_before="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
  assert_equal "$(git -C "$WORK" status --porcelain)" "$status_before"
  assert_equal "$(git -C "$WORK" tag | sort | tr '\n' ' ')" "$tags_before"
  assert_equal "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)" "$refs_before"
  assert_equal "$(git -C "$WORK" branch --show-current)" "feature/v1.5"
}

# ── merge ────────────────────────────────────────────────────────────────────

@test "merge: fast-forwards the default branch and leaves the checkout on it" {
  local feature_sha
  feature_sha="$(git -C "$WORK" rev-parse feature/v1.5)"

  release merge --source feature/v1.5

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
  assert_equal "$(git -C "$WORK" rev-parse main)" "$feature_sha"
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$feature_sha"
}

@test "merge: a conflict is aborted, the branch restored, and nothing tagged" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'feature side\n' > "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feature side"
  git -C "$WORK" switch -q main
  printf 'main side\n' > "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "main side"
  git -C "$WORK" switch -q feature/v1.5

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'FATAL:'
  assert_equal "$(git -C "$WORK" branch --show-current)" "feature/v1.5"
  assert_equal "$(git -C "$WORK" status --porcelain)" ""
  refute [ -e "$WORK/.git/MERGE_HEAD" ]
  assert_equal "$(git -C "$WORK" tag | sort | tr '\n' ' ')" "1.0.0 1.1.0 1.2.0 1.3.0 1.4.0 "
}

@test "merge: running on the default branch is a no-op" {
  git -C "$WORK" switch -q main
  local head_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"

  release merge --source main

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
}

# ── merge: fixup squashing ───────────────────────────────────────────────────

@test "merge: folds fixup commits into their targets before merging" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  printf 'fixed\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "fixup! more feature work"

  release merge --source feature/v1.5

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
  run git -C "$WORK" log --format=%s main
  refute_output --partial 'fixup!'
  assert_output --partial 'more feature work'
  # The fixup's content is folded into its target, not lost.
  assert_equal "$(cat "$WORK/feature.txt")" "$(printf 'feature\nmore\nfixed')"
  # 5 tagged commits + "feature work" + "more feature work" (fixup folded in).
  assert_equal "$(git -C "$WORK" rev-list --count main)" "7"
}

@test "merge: refuses to publish memory-vault commits" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'note\n' > "$WORK/.agents/memory/latent/note.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): capture the session"
  local before
  before="$(git -C "$WORK" rev-parse main)"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'memory-vault'
  assert_equal "$(git -C "$WORK" rev-parse main)" "$before"
}

@test "merge: refuses a non-string devbot_dir" {
  git -C "$WORK" switch -q feature/v1.5
  printf '{ "devbot_dir": [] }\n' > "$WORK/.devbot.project.jsonc"
  git -C "$WORK" add .devbot.project.jsonc
  git -C "$WORK" commit -qm "chore: array devbot_dir"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'non-string'
}

@test "merge: fails closed when the project config cannot be read" {
  git -C "$WORK" switch -q feature/v1.5
  printf '{ not json\n' > "$WORK/.devbot.project.jsonc"
  git -C "$WORK" add .devbot.project.jsonc
  git -C "$WORK" commit -qm "chore: broken project config"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'refusing to guess'
}

@test "merge: resolves a custom vault when DEV_BOT_ROOT is unset" {
  git -C "$WORK" switch -q feature/v1.5
  printf '{ "devbot_dir": ".dev" }\n' > "$WORK/.devbot.project.jsonc"
  mkdir -p "$WORK/.dev/memory/latent"
  printf 'note\n' > "$WORK/.dev/memory/latent/custom.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): custom vault capture"

  run env -u DEV_BOT_ROOT bash -c "cd '$WORK' && bash '$SCRIPT' merge --source feature/v1.5"

  assert_failure
  assert_output --partial 'memory-vault'
}

@test "vault guard: detects a vault file added and later deleted" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'note\n' > "$WORK/.agents/memory/latent/tmp.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): add a note"
  git -C "$WORK" rm -q .agents/memory/latent/tmp.md
  git -C "$WORK" commit -qm "chore(memory): drop the note"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5"
  assert_success
  assert_output --partial 'tmp.md'
}

@test "merge: refuses a local default that is ahead of origin" {
  git -C "$WORK" switch -q main
  git -C "$WORK" commit -q --allow-empty -m "chore: unrelated local commit"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'ahead of origin'
}

@test "merge: refuses a fixup whose target cannot be autosquashed" {
  git -C "$WORK" switch -q feature/v1.5
  git -C "$WORK" commit -q --allow-empty -m "fixup! no such target"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'unmatched fixup'
}

@test "vault guard: rejects an absolute devbot directory" {
  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 /tmp/state"
  assert_failure
  assert_output --partial 'absolute'
}

@test "vault guard: rejects repeated separators in the devbot directory" {
  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 '.dev//state'"
  assert_failure
  assert_output --partial 'non-canonical'
}

@test "vault guard: rejects a non-canonical devbot directory" {
  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 'foo/../.agents'"
  assert_failure
  assert_output --partial 'non-canonical'
}

@test "vault guard: normalises a trailing separator in the devbot directory" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.dev/memory/latent"
  printf 'note\n' > "$WORK/.dev/memory/latent/slashed.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): custom vault capture"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 .dev/"
  assert_success
  assert_output --partial '.dev/memory/latent/slashed.md'
}

@test "merge: fails closed when the effective global config cannot be read" {
  printf '{ not json\n' > "$SANDBOX/broken-global.jsonc"

  run env DEV_BOT_GLOBAL_CONFIG="$SANDBOX/broken-global.jsonc" \
    bash -c "cd '$WORK' && bash '$SCRIPT' merge --source feature/v1.5"

  assert_failure
  assert_output --partial 'refusing to guess'
}

@test "vault guard: detects a dot-rooted vault" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/memory/latent"
  printf 'note\n' > "$WORK/memory/latent/rooted.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): dot-rooted capture"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 ."
  assert_success
  assert_output --partial 'memory/latent/rooted.md'
}

@test "vault guard: fails closed when the base ref is unavailable" {
  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/does-not-exist main"
  assert_failure
  assert_output --partial 'is unavailable'
}

@test "merge: refuses unsquashed fixups stranded on the default branch" {
  git -C "$WORK" switch -q main
  printf 'local work\n' >> "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore: local work"
  git -C "$WORK" commit -q --allow-empty -m "fixup! chore: local work"

  release merge --source main

  assert_failure
  assert_output --partial 'unsquashed fixup'
}

@test "merge: refuses stranded vault commits on the default-branch no-op path" {
  git -C "$WORK" switch -q main
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'note\n' > "$WORK/.agents/memory/latent/stranded.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): stranded capture"

  release merge --source main

  assert_failure
  assert_output --partial 'memory-vault'
}

@test "vault guard: detects an older vault under another state dir" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'note\n' > "$WORK/.agents/memory/latent/old.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): old vault"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 .dev"
  assert_success
  assert_output --partial '.agents/memory/latent/old.md'
}

@test "merge: resolves a custom vault from the main checkout for a linked worktree" {
  git -C "$WORK" switch -q main
  # The project config is gitignored, so it exists only in the main checkout.
  printf '.devbot.project.jsonc\n' >> "$WORK/.git/info/exclude"
  printf '{ "devbot_dir": ".dev" }\n' > "$WORK/.devbot.project.jsonc"
  git -C "$WORK" worktree add -q "$SANDBOX/wt" -b feature/dev feature/v1.5
  mkdir -p "$SANDBOX/wt/.dev/memory/latent"
  printf 'note\n' > "$SANDBOX/wt/.dev/memory/latent/custom.md"
  git -C "$SANDBOX/wt" add -A
  git -C "$SANDBOX/wt" commit -qm "chore(memory): custom vault"

  release merge --source feature/dev

  assert_failure
  assert_output --partial 'memory-vault'
}

@test "vault guard: refuses a devbot directory git must quote" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.dev\\bot/memory/latent"
  printf 'note\n' > "$WORK/.dev\\bot/memory/latent/bs.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): backslash vault"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5 '.dev\\bot'"
  assert_failure
  assert_output --partial 'quoted'
}

@test "vault guard: fails closed on a quoted path" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'x\n' > "$WORK/.agents/memory/latent/note"$'\n'"name.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore: newline path"

  run bash -c "cd '$WORK' && source '$MODULE_DIR/tools/git.sh' && _vault_paths origin/main feature/v1.5"
  assert_failure
  assert_output --partial 'quoted'
}

@test "merge: refuses a source that is behind origin" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'extra\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "extra feature work"
  git -C "$WORK" push -q origin feature/v1.5
  git -C "$WORK" reset -q --hard HEAD~1

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'does not match origin'
}

@test "merge: refuses a dirty source worktree" {
  git -C "$WORK" worktree add -q "$SANDBOX/wt" -b feature/wt feature/v1.5
  printf 'uncommitted\n' >> "$SANDBOX/wt/feature.txt"

  release merge --source feature/wt

  assert_failure
  assert_output --partial 'uncommitted changes'
}

@test "merge: refuses when the default branch lives in another worktree" {
  git -C "$WORK" switch -q main
  git -C "$WORK" worktree add -q "$SANDBOX/wt" -b feature/wt feature/v1.5

  run bash -c "cd '$SANDBOX/wt' && bash '$SCRIPT' merge --source feature/wt"

  assert_failure
  assert_output --partial 'run this from that checkout'
}

@test "merge: handles a source worktree path containing a space" {
  git -C "$WORK" worktree add -q "$SANDBOX/wt with space" -b feature/sp feature/v1.5
  printf 'more\n' >> "$SANDBOX/wt with space/feature.txt"
  git -C "$SANDBOX/wt with space" add -A
  git -C "$SANDBOX/wt with space" commit -qm "more feature work"
  printf 'fixed\n' >> "$SANDBOX/wt with space/feature.txt"
  git -C "$SANDBOX/wt with space" add -A
  git -C "$SANDBOX/wt with space" commit -qm "fixup! more feature work"

  release merge --source feature/sp

  assert_success
  run git -C "$WORK" log --format=%s main
  refute_output --partial 'fixup!'
  assert_output --partial 'more feature work'
}

@test "merge: squashes a source checked out in another worktree" {
  git -C "$WORK" worktree add -q "$SANDBOX/wt" -b feature/wt feature/v1.5
  printf 'more\n' >> "$SANDBOX/wt/feature.txt"
  git -C "$SANDBOX/wt" add -A
  git -C "$SANDBOX/wt" commit -qm "more feature work"
  printf 'fixed\n' >> "$SANDBOX/wt/feature.txt"
  git -C "$SANDBOX/wt" add -A
  git -C "$SANDBOX/wt" commit -qm "fixup! more feature work"

  release merge --source feature/wt

  assert_success
  run git -C "$WORK" log --format=%s main
  refute_output --partial 'fixup!'
  assert_output --partial 'more feature work'
}

@test "merge: squashes the named source even when another branch is checked out" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  printf 'fixed\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "fixup! more feature work"
  git -C "$WORK" switch -q main

  release merge --source feature/v1.5

  assert_success
  run git -C "$WORK" log --format=%s main
  refute_output --partial 'fixup!'
  assert_output --partial 'more feature work'
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
}

@test "merge: refuses when the local default carries unpushed vault commits" {
  git -C "$WORK" switch -q main
  mkdir -p "$WORK/.agents/memory/latent"
  printf 'note\n' > "$WORK/.agents/memory/latent/local.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "chore(memory): local capture"
  local before
  before="$(git -C "$WORK" rev-parse main)"

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'unpushed memory-vault'
  assert_equal "$(git -C "$WORK" rev-parse main)" "$before"
}

@test "merge: ignores a non-vault directory named memory" {
  git -C "$WORK" switch -q feature/v1.5
  mkdir -p "$WORK/docs/memory/reference"
  printf 'guide\n' > "$WORK/docs/memory/reference/guide.md"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "docs: add a memory guide"

  release merge --source feature/v1.5

  assert_success
}

@test "merge: reports the fixups it squashed" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  git -C "$WORK" commit -q --allow-empty -m "fixup! more feature work"

  release merge --source feature/v1.5

  assert_success
  assert_output --partial 'squashed'
}

@test "plan: reports the fixup commits that will be squashed, mutating nothing" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  git -C "$WORK" commit -q --allow-empty -m "fixup! more feature work"
  local head_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '1 fixup commit'
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
}

@test "plan: a branch with no fixups reports none to squash" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'Squash:** none'
}

# ── tag ──────────────────────────────────────────────────────────────────────

@test "tag: creates an annotated tag carrying the notes' markdown heading" {
  release tag --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" cat-file -t 1.5.0)" "tag"

  run git -C "$WORK" cat-file tag 1.5.0
  assert_output --partial '# Release v1.5.0'
  assert_output --partial 'Removed model downloads'
}

@test "tag: refuses a version that already exists locally" {
  git -C "$WORK" tag 1.5.0

  release tag --version 1.5.0 --notes-file "$NOTES"

  assert_failure
  assert_output --partial 'FATAL:'
}

# ── push ─────────────────────────────────────────────────────────────────────

@test "push: sends the default branch and the tag to two remotes" {
  release merge --source feature/v1.5
  assert_success
  release tag --version 1.5.0 --notes-file "$NOTES"
  assert_success

  release push --version 1.5.0 --branch main --remotes origin,second

  assert_success
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
  assert_equal "$(git -C "$SECOND" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "$(git -C "$WORK" rev-parse main)"
  assert_equal "$(git -C "$SECOND" rev-parse refs/heads/main)" "$(git -C "$WORK" rev-parse main)"
}

@test "push: an unreachable remote does not stop the others and is reported" {
  release merge --source feature/v1.5
  release tag --version 1.5.0 --notes-file "$NOTES"
  git -C "$WORK" remote add broken "$SANDBOX/nope.git"

  release push --version 1.5.0 --branch main --remotes origin,broken

  assert_failure
  assert_output --partial 'origin'
  assert_output --partial 'broken'
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
}

# ── tag-only: an already-merged release ─────────────────────────────────────

@test "plan --tag-only: works from a detached HEAD and plans no branch push" {
  git -C "$WORK" switch -q --detach origin/main

  release plan --tag-only --version 1.5.0 --ref origin/main --notes-file "$NOTES" --remotes origin

  assert_success
  assert_output --partial "Tag:** \`1.5.0\` (annotated)"
  assert_output --partial "Branch push:** none"
  refute_output --partial "Source branch"
  refute_output --partial "Merge:"
}

@test "tag --ref: tags the given commit, not HEAD" {
  local target
  target="$(git -C "$WORK" rev-parse origin/main)"

  release tag --tag-only --version 1.5.0 --ref "$target" --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse refs/tags/1.5.0^{commit})" "$target"
  [ "$(git -C "$WORK" rev-parse HEAD)" != "$target" ]
}

@test "tag --tag-only: refuses a branch ref — only the approved SHA is pinned" {
  release tag --tag-only --version 1.5.0 --ref origin/main --notes-file "$NOTES"

  assert_failure
  assert_output --partial "needs the full commit SHA from the plan"
  run git -C "$WORK" rev-parse --verify --quiet refs/tags/1.5.0
  [ "$status" -ne 0 ]
}

@test "tag --ref: an unresolvable ref fails without creating a tag" {
  release tag --tag-only --version 1.5.0 --ref 1111111111111111111111111111111111111111 --notes-file "$NOTES"

  assert_failure
  assert_output --partial "is not in this checkout"
  run git -C "$WORK" rev-parse --verify --quiet refs/tags/1.5.0
  [ "$status" -ne 0 ]
}

@test "push --tag-only: sends the tag and leaves the remote branch alone" {
  local before target
  before="$(git -C "$ORIGIN" rev-parse refs/heads/main)"
  target="$(git -C "$WORK" rev-parse origin/main)"
  release tag --tag-only --version 1.5.0 --ref "$target" --notes-file "$NOTES"
  assert_success

  release push --tag-only --version 1.5.0 --remotes origin

  assert_success
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/tags/1.5.0^{commit})" \
    "$(git -C "$WORK" rev-parse origin/main)"
  # The branch was not pushed: still where it was before.
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "$before"
}

@test "push --tag-only: a failing remote's remediation names only the tag" {
  local target
  target="$(git -C "$WORK" rev-parse origin/main)"
  release tag --tag-only --version 1.5.0 --ref "$target" --notes-file "$NOTES"
  assert_success

  release push --tag-only --version 1.5.0 --remotes nope

  assert_failure
  assert_output --partial "git push <remote> refs/tags/1.5.0"
  refute_output --partial "git push <remote> main"
}

@test "plan --tag-only: a remote-tracking ref is read from the remote, not the stale local ref" {
  # Advance origin/main without fetching in WORK: its refs/remotes/origin/main
  # still points at the pre-merge commit.
  local clone="$SANDBOX/clone"
  git clone -q "$ORIGIN" "$clone"
  git -C "$clone" config user.email "test@test.com"
  git -C "$clone" config user.name "Test"
  git -C "$clone" config commit.gpgsign false
  printf 'merged\n' > "$clone/merged.txt"
  git -C "$clone" add -A
  git -C "$clone" commit -qm "merged upstream"
  git -C "$clone" push -q origin main
  local remote_tip stale_tip
  remote_tip="$(git -C "$ORIGIN" rev-parse refs/heads/main)"
  stale_tip="$(git -C "$WORK" rev-parse refs/remotes/origin/main)"
  [ "$remote_tip" != "$stale_tip" ]

  release plan --tag-only --version 1.5.0 --ref origin/main --notes-file "$NOTES" --remotes origin

  assert_success
  assert_output --partial "**Target:** \`${remote_tip}\`"
  refute_output --partial "**Target:** \`${stale_tip}\`"
}

@test "tag --tag-only: an approved SHA missing locally gets the fetch remediation" {
  release tag --tag-only --version 1.5.0 \
    --ref 1111111111111111111111111111111111111111 --notes-file "$NOTES"

  assert_failure
  assert_output --partial "is not in this checkout — fetch the release branch first"
}

@test "tag --tag-only: accepts the native object-id length (SHA-256 repositories)" {
  local sha256_repo="$SANDBOX/sha256"
  git init -q --object-format=sha256 "$sha256_repo" 2>/dev/null \
    || skip "git without SHA-256 object-format support"
  git -C "$sha256_repo" config user.email "test@test.com"
  git -C "$sha256_repo" config user.name "Test"
  git -C "$sha256_repo" config commit.gpgsign false
  printf 'x\n' > "$sha256_repo/f.txt"
  git -C "$sha256_repo" add -A
  git -C "$sha256_repo" commit -qm "sha256 commit"
  local sha notes
  sha="$(git -C "$sha256_repo" rev-parse HEAD)"
  [ ${#sha} -eq 64 ]
  notes="$SANDBOX/sha256-notes.md"
  printf '# Release v1.5.0\n' > "$notes"

  run bash -c "cd '$sha256_repo' && bash '$SCRIPT' tag --tag-only --version 1.5.0 --ref '$sha' --notes-file '$notes'"

  assert_success
  assert_equal "$(git -C "$sha256_repo" rev-parse refs/tags/1.5.0^{commit})" "$sha"
}

@test "plan: --ref without --tag-only is rejected — the normal plan has no ref" {
  release plan --version 1.5.0 --ref HEAD --notes-file "$NOTES" --remotes origin

  assert_failure
  assert_output --partial "applies only with --tag-only"
}

@test "tag: --ref without --tag-only is rejected — never tag an unapproved target" {
  release tag --version 1.5.0 --ref HEAD --notes-file "$NOTES"

  assert_failure
  assert_output --partial "applies only with --tag-only"
  run git -C "$WORK" rev-parse --verify --quiet refs/tags/1.5.0
  [ "$status" -ne 0 ]
}

@test "push: --ref is rejected — push sends a created tag" {
  release push --version 1.5.0 --ref HEAD --remotes origin

  assert_failure
  assert_output --partial "--ref does not apply"
}

@test "plan --tag-only: an unreachable remote reports the fetch remediation" {
  git -C "$WORK" remote add broken "$SANDBOX/does-not-exist.git"

  release plan --tag-only --version 1.5.0 --ref broken/main --notes-file "$NOTES" --remotes broken

  assert_failure
  assert_output --partial "cannot verify 'broken/main' on 'broken'"
  assert_output --partial "fetch it, or pass the commit SHA"
}

# ── plan formatting ─────────────────────────────────────────────────────────

@test "plan: the remote list in the approval step reads as a comma-separated list" {
  release plan --version 1.5.0 --notes-file "$NOTES" --remotes origin,second

  assert_success
  assert_output --partial "to \`origin\`, \`second\`"
}

@test "plan --tag-only: the remote list reads as a comma-separated list" {
  local target
  target="$(git -C "$WORK" rev-parse origin/main)"

  release plan --tag-only --version 1.5.0 --ref "$target" --notes-file "$NOTES" --remotes origin,second

  assert_success
  assert_output --partial "to \`origin\`, \`second\`"
}
