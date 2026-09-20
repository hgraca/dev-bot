---
date: 2026-09-16
keywords: ["docker", "floating-tag", "image-pinning", "ci"]
trigger-on: ["docker-image-tag", "ci-service-container"]
---

## A floating image tag turns an upstream image change into a silent CI outage

Declaring a container as `image: mongo:8` (or any bare major tag) means the image is re-resolved on every run, so an unrelated upstream patch release can break CI with no commit in the repository at all. Real case: `mongo:8` began resolving to a build that cannot start on kernel 6.19+, turning a green workflow into a failing one whose error pointed at the database rather than the image. Pin deliberately - a specific patch, or at minimum a major known to be unaffected - and put the reason in a comment beside the tag, so the next person does not helpfully bump it back into the bug. A repo where several workflows pin different majors of the same image is itself a signal: the jobs on the floating or newly-broken tag are the ones to suspect first, and the ones on an older pinned major are useful as a working comparison on the very same runner.
