---
date: 2026-11-09
keywords: ["git", "version-sort", "v:refname", "tags"]
trigger-on: ["git-tag-version-sort"]
---

## `--sort=v:refname` puts non-version tags after every version tag

`git tag --sort=v:refname` compares ref names with a version-aware ordering: numeric
components compare numerically (`1.9.0` before `1.10.0`, which plain `refname` gets wrong),
digits sort before letters, and a bare name with no digits at all (`nightly`, `latest`)
sorts after every purely numeric name. So in an ascending version-sorted list, tags like
`nightly`, `release-2026-11-09` or `build.7` appear _after_ the whole `1.x` line — they
cannot fall between two version tags.

Pre-release suffixes are the opposite case: `1.1.0-rc1` sorts _between_ `1.1.0` and
`1.2.0`, and so does a four-component tag such as `1.1.0.1`. Any code slicing a range out
of that list must filter by shape (not merely take neighbours) if such tags must not
appear in the range; the sort order alone does not exclude them.
