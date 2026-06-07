---
date: 2026-06-18
keywords: ["k8s", "kube-linter", "github-releases", "shell", "grep"]
---

# GitHub releases with both raw binary and tar.gz — grep must target .tar.gz explicitly

kube-linter publishes both `kube-linter-linux` (raw binary) and `kube-linter-linux.tar.gz` (archive)
as release assets. Grepping for `${os}` (e.g. `linux`) matches both, and `head -1` picks the raw binary
first. The subsequent `tar xzf` fails with `not in gzip format` because the raw binary is not gzipped.

Fix: grep for `${os}\.tar\.gz` instead of bare `${os}` to select only the archive asset.
The `grep -v sha256` guard (if present) can stay as a safety net.
