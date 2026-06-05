---
date: 2026-06-16
keywords: ["shell", "yq", "apt", "brew", "installation"]
---

## yq (mikefarah/yq) cannot be installed via apt — apt's yq is kislyuk/yq (different CLI)

On Linux, `apt install yq` installs kislyuk/yq (Python wrapper around jq), not mikefarah/yq (Go-based). These have incompatible CLI interfaces. For mikefarah/yq: use `brew install yq` on macOS, or `wget` from GitHub releases on Linux (`https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64`). Always verify with `yq --version` — mikefarah/yq reports version like `v4.x.x`, kislyuk/yq shows different output.
