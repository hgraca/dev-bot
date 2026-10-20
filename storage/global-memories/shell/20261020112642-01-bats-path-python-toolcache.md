---
date: 2026-10-20
keywords: ["shell", "bats", "path", "github-actions", "python-toolcache"]
trigger-on: ["bats-ci-path"]
---

## Narrowing PATH to the python directory drops coreutils on GitHub runners

BATS tests that simulate a missing tool often set `export PATH="$(dirname "$(command -v python3)")"`. On a GitHub runner `python3` lives in `/opt/hostedtoolcache/Python/.../bin`, which contains no `bash`, `cat`, `chmod` or `mkdir`; the test then fails with `env: 'bash': No such file or directory` or `cat: command not found` (status 127), which reads as a broken test rather than an environment bug. Locally `/usr/bin/python3` hides it because that directory also holds coreutils. Append the system directories to the narrowed PATH — `PATH="${stub_dir}:$(dirname "$(command -v python3)"):/usr/bin:/bin"` — which is portable (macOS has the same directories) and keeps the stub first. A single-prefix node install hits the same trap when a test hides `prettier`.
