---
title: "Argo CD"
description: "Install the argocd CLI, connect to a cluster, upgrade Argo CD in place, and rotate its TLS certificate."
skills: ["argocd"]
tools: ["argocd-install", "argocd-start", "argocd-upgrade", "argocd-restart"]
---

Operational scripts for an Argo CD installation. Each is a normal CLI a human can run, and each is exposed to agents through `devbot-tools` with a JSON mode (`--json`) and stable exit codes.

## Tools

| Tool             | Purpose                                                                            |
| ---------------- | ---------------------------------------------------------------------------------- |
| `argocd-install` | Install or verify the `argocd` CLI (arch-aware, checksummed, no profile edits)     |
| `argocd-start`   | Connect to a cluster (port-forward when needed) and list applications              |
| `argocd-upgrade` | Upgrade Argo CD in place from the official manifests, with backup and verification |
| `argocd-restart` | Restart the server so a renewed TLS certificate is served, then verify             |

## How agents use it

The agent calls the MCP tools (or the scripts) with explicit arguments. Cluster-changing tools require `--context` and refuse a context that cannot perform the required write. Non-interactive upgrade runs must pass `--yes`; the script will not silently skip the confirmation.

## Configuration

Nothing is required. `argocd-install` honours `ARGOCD_BIN_DIR` (default `~/.local/bin`); `argocd-start` honours `ARGOCD_AUTH_TOKEN`. Cluster access comes from the project's kubeconfig/contexts.

## See also

- [Module reference](/module-reference)
- [Kubernetes access](/modules/agentic/k8s) — cluster context rules
