---
name: devbot:gh-release
description: Make a GitHub release — tag the current branch, push it, and publish the release after showing you the plan
---

Load the `devbot:gh-release` skill and follow it.

The optional argument (`$1`) is the version to release, e.g. `1.6.0`. When it is
absent, the skill resolves the next minor from the remote's newest tag.
