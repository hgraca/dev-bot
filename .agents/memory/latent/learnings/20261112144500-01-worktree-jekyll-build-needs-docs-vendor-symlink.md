---
date: 2026-11-12
keywords: ["jekyll", "worktree", "bundle", "vendor", "docs-site"]
---

# Building the docs site from a linked worktree needs a docs/vendor symlink

`worktree.sh create` hard-links `vendor/` and `node_modules/` at the repo **root**, but the Jekyll bundle lives at `docs/vendor/bundle` (`.bundle/config` sets `BUNDLE_PATH: "vendor/bundle"`) — a fresh worktree therefore has no gems.

Pointing `BUNDLE_PATH` at the main checkout does **not** work:

```bash
BUNDLE_PATH=/<main>/docs/vendor/bundle bundle exec jekyll build
# Could not find jekyll-4.4.1, ... in locally installed gems
# bundler: command not found: jekyll
```

Symlink the directory instead, relative to the worktree, so `.bundle/config`'s relative `vendor/bundle` resolves through it:

```bash
ln -s /<main>/docs/vendor <worktree>/docs/vendor
cd <worktree>/docs && bundle exec jekyll build
rm <worktree>/docs/vendor   # before committing
```

`docs/vendor` is **not** gitignored (only `docs/_site/` is), so the symlink shows as untracked and must be removed before `git add` or the commit picks it up. The docs gather step (`src/agentic/docs/tools/gather-module-docs.sh`) runs fine in a worktree and writes only gitignored output.
