---
date: 2026-08-29
keywords: ["bats", "install.sh", "mockbin", "testing", "bootstrap"]
---

# Testing the standalone install.sh path: sandbox copy + mockbin on PATH

The root `install.sh` skips its clone/pull logic when run from inside a clone
(`PWD/bin/install.sh` exists), so BATS tests cannot exercise the standalone
path by invoking the real script from the repo. The working pattern: copy
`install.sh` into a `mktemp -d` sandbox, `cd` there (no `bin/install.sh`), and
mock `curl` (GitHub API responses) + `git` (log args to a file, create the
install tree on `clone`) via a `mockbin/` dir prepended to `PATH`. The mock
`git` must create `${install_dir}/bin/install.sh` and `bin/devbot` so the
in-repo-installer and CLI-link steps succeed. Same trick applies to module
installers that branch on `command -v`: stub the binary in mockbin to pin the
skip path. Gotcha: host-installed binaries (e.g. prettier in
`~/.npm-global/bin`) still resolve after mockbin is prepended — build the test
PATH from only the dirs holding required tools (python3/node/npm) plus mockbin
to make `command -v` results controllable. See `bin/tests/install_bootstrap_tests.bats`
and `src/agentic/format-json/tests/install_tests.bats` for examples.
