---
date: 2026-05-03
keywords: ["otel"]
---

## M-FLOW-001: Don't use `helm --wait` for image-heavy charts in Makefiles

`make otel-demo-deploy` with `--wait --timeout 8m` failed on first run because 18 container images need pulling.
For charts with many images (OTel Demo has ~15), skip `--wait` in Makefile targets. Helm returns immediately after submitting resources; pods start in background. Use a separate `make status` or `kubectl wait` if blocking is needed. The `_up-fresh` flow already ends with `make status` which shows pod state.
