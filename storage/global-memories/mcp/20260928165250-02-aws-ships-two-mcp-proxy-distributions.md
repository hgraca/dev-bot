---
date: 2026-09-28
keywords: ["mcp", "mcp-proxy-for-aws", "uv-tool", "aws"]
trigger-on: ["aws-mcp-proxy-install"]
---

## AWS ships two `mcp-proxy-for-aws` distributions — install the `-cli` one

For CLI/`uvx` use AWS publishes `mcp-proxy-for-aws-cli` alongside the `mcp-proxy-for-aws` library. The `-cli` distribution is the designated CLI artifact: it pins its **entire** dependency tree to exact versions (every `Requires-Dist` is `==`), so one version resolves identically on every machine, whereas the bare library leaves ranges open and two machines on the same version can drift. Its console script is named `mcp-proxy-for-aws-cli` (it does **not** expose a `mcp-proxy-for-aws` binary), and `uv tool list` keys on it as `mcp-proxy-for-aws-cli v<version>`, so any tool or test fake keyed on the binary name must be renamed with it. The first `-cli` release is 1.6.5, so switching from a 1.6.4 library pin requires a version bump. It accepts the same flags as the library (`--profile`, `--region`, `--metadata`, endpoint positional).
