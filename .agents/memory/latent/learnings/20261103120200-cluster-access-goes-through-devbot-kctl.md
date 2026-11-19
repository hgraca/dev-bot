---
date: 2026-11-03
keywords:
  ["kubectl", "kubeconfig", "devbot kube", "devbot kctl", "kctl mcp", "rbac"]
aliases: ["cluster access", "gete-prod-ro", "pods/exec denied"]
---

# Cluster access goes through `devbot kctl`, and agents use the kctl MCP

## The generated kubeconfig is not guessable

`init.sh` writes `~/.kube/devbot/<project_name>-<8-hex>.yaml` (the hash is of the absolute project path) plus a `.env` that contains **only** `export KUBECONFIG=…` — no credentials. Contexts come from the global catalogue's `context` field (`gete-prod-ro`, `gete-staging-rw`). Before `devbot kctl` existed, the module's `docs.md` named a non-existent `<project>.yaml` and `k8s-prod-ro`, so agents fell back to the SSO contexts in `~/.kube/config` and hit `Token has expired and refresh failed`.

## RBAC boundaries

The identity lands in `gete-agents-readonly` (cluster-wide get/list/watch, no secrets, exec, port-forward or token creation) and `gete-agents-writer` (staging only, namespaced to `default`). `pods/exec` is denied by design — use the `datasources` module or SigNoz metrics instead of exec-ing into a pod. Because the writer Role is namespaced to `default`, `core`, `kube-system`, `argocd` and `otel-collector` stay read-only even on staging.

## The command is `kctl`; the agents' path is the MCP

`devbot kube` was renamed `devbot kctl`, and `kctl exec <cluster>` is the cluster-scoped form the per-cluster MCP servers call. Agents do not run the CLI at all: each rendered cluster is a `kctl-<cluster>` MCP server whose single `kubectl` tool applies that cluster's context. `devbot kctl env` and `contexts` stay available for diagnostics.

## Which layer enforces what

The prohibition has three layers, and the guard is only one of them. Each
layer is blind to something the others cover:

| Layer                                   | Enforces                                                                                                                              | Blind to                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| module memory (`active/modules/k8s.md`) | the policy: no kubectl in any channel, MCP only                                                                                       | nothing — an agent follows it, or it does not               |
| guard rules (dist configs)              | shell command strings seen by the bash tool / PTY: `kubectl` (also by path or `VAR=` prefix), `devbot kctl run\|exec`                 | MCP tool calls, and any shell a script, Makefile or CI runs |
| the MCP server (`kctl-<cluster>`)       | the target: it applies one cluster's context and refuses overriding flags, a leading `kubectl`, and `kubectl config` writes / `--raw` | what happens outside the tool                               |

So the guard is a backstop on the shell, not a sandbox: a `kubectl` hidden in a script body is caught by nothing but the memory. The kubeconfig is module-owned — writes to it are refused by the server, and `devbot reinit` is how it changes.
