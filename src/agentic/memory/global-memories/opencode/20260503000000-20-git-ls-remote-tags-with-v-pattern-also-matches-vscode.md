`git ls-remote --tags --sort=-v:refname ... 'refs/tags/v*'` matches `vscode-v0.0.13` which sorts above `v1.14.33`. Also `--sort=-v:refname` doesn't do proper semver sorting on the remote. Fix: use pattern `'refs/tags/v[0-9]*'` to exclude non-version tags, pipe through `sed 's|.*refs/tags/v||' | sort -V -r | head -1` for proper version sorting locally.

Using `git ls-remote --tags ... 'refs/tags/v*'` matches both version tags (`v1.14.33`) and unrelated tags (`vscode-v1.2.3`). Fix: use `'refs/tags/v[0-9]*'` pattern to only match tags starting with `v` followed by a digit.

When querying opencode repo tags, `refs/tags/v*` matches both `v1.14.33` and `vscode-v1.2.3`. This causes `sort -V -r | head -1` to return the wrong version. Fix: use `refs/tags/v[0-9]*` pattern to only match numeric version tags.
