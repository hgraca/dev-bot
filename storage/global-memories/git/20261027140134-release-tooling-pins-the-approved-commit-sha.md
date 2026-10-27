---
date: 2026-10-27
keywords: ["git", "release-tooling", "ls-remote", "tag", "cat-file"]
aliases: ["tag-only release", "approved commit sha", "stale origin/main", "annotated tag pinning"]
trigger-on: ["release-tooling", "git-tag", "tag-approval"]
---

## Release tooling must pin the approved commit SHA

A release that is approved as "tag `origin/main`" and later executes `git tag <ref>` re-resolves a mutable branch ref, so a merge landing in between makes the tag land on a commit nobody approved — and a local `origin/main` tracking ref that predates the merge advertises the pre-merge commit in the first place. Resolve the remote tip without touching refs (`git ls-remote <remote> refs/heads/<branch>`, read-only even inside a "the plan mutates nothing" step), print the full commit id in the plan, and require that id for the write: pass `ref^{commit}` to `git tag` so an annotated tag supplied as the ref cannot produce a nested tag. Distinguish "approved but not fetched" from "invalid": `git rev-parse <sha>` fails for both, while `git cat-file -e <sha>^{commit}` succeeds only when the object is local — check it first so the caller gets "fetch the release branch" rather than a generic resolution error. Derive the expected id length from the repository (`git rev-parse HEAD`) instead of hardcoding 40, or SHA-256 repositories are rejected.
