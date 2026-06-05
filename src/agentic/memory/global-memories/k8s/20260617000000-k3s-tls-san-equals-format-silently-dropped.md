---
date: 2026-06-17
keywords: ["k8s", "k3s", "k3d", "tls-san", "certificate"]
---

## K3s v1.35.5 drops --tls-san=value (equals format) when other --tls-san args use space format

K3s v1.35.5's flag parser silently ignores `--tls-san=value` (equals format) when other `--tls-san` arguments on the same command line use space format (`--tls-san value`). K3d injects `--tls-san 0.0.0.0` and `--tls-san k3d-obs-signoz-serverlb` with space format, so any user-supplied `--tls-san=IP` (equals format) in `k3d cluster-config.yaml` `extraArgs` is dropped — the TLS certificate won't include that SAN. Fix: always use space format (`--tls-san ${K3S_TLS_SAN}`) and add a post-render sed cleanup to remove the arg entirely when the variable is empty to avoid a trailing-whitespace line that may break k3s parsing.
