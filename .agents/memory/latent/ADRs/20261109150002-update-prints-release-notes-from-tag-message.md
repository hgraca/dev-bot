---
date: 2026-11-09
keywords: ["release-notes", "devbot-update", "annotated-tag", "devbot-cli"]
see: ["ADRs/20260829193000-install-release-tag-fallback-main.md"]
---

## `devbot update` prints release notes read from the annotated tag message

`devbot update` ends a real move by printing the notes of every release between the version
it left (exclusive) and the version it landed on (inclusive), oldest first. The notes are
not read from files: `release.v<VERSION>.no-vcs.md` is gitignored (`*no-vcs*`), so a
consumer machine never has a copy. Instead the annotated tag message is the transport —
`tag.sh` creates every release tag with `git tag -a --cleanup=whitespace -F <release file>`,
so `git tag -l --format='%(contents)' <tag>` returns the release file verbatim, and
`_fetch_tags` has already brought all tags down before the notes are needed. This was
preferred over `gh release view` (needs `gh` and auth, breaks offline) and over committing
the release files (they are deliberately local artifacts).

Consequences worth remembering. Only annotated tags carry notes: a lightweight tag holds its
commit message, which can itself start with `# Release v`, so the reader checks
`git cat-file -t <tag>` for `tag` and then the `# Release v` heading. Tags are filtered to
the release shapes `X.Y.Z` and `0.X.Y.Z` (`_normalise_version`'s rule) because a pre-release
tag such as `1.1.0-rc1` sorts inside the range. A downgrade prints only the target's notes,
and an untagged source (`_describe_head` falling back to a short sha) prints the target's
notes plus a line saying the range could not be anchored. Releases before `1.5.0` predate the
convention and print as "no release notes recorded" rather than their commit subject.
