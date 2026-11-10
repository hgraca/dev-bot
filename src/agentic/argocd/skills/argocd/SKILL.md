---
name: devbot:argocd
description: "Use when operating an Argo CD installation — installing the CLI, connecting to a cluster, or rotating its TLS certificate."
---

# Argo CD

Three scripts for operating an Argo CD installation: install the CLI, connect to a cluster, and restart the server after a certificate rotation. Each is runnable directly (human) and exposed as a `devbot-tools` MCP tool (agent).

## When to Use

| Situation                                            | Tool             |
| ---------------------------------------------------- | ---------------- |
| The `argocd` CLI is missing or outdated              | `argocd-install` |
| You need application status from a cluster           | `argocd-start`   |
| A renewed server certificate is not being served yet | `argocd-restart` |

Anything that changes a cluster needs a kube context that can authenticate there. `argocd-restart` additionally needs permission to patch Deployments — a read-only context is refused by the preflight, not by a failed apply.

## Tools

### `argocd-install` — the CLI binary

```bash
argocd-install.sh [--version <tag>] [--bin-dir <dir>] [--force] [--add-to-path] [--json]
```

Detects OS and architecture, resolves the latest release unless `--version` pins one, verifies the SHA-256 from `cli_checksums.txt`, and installs to `$ARGOCD_BIN_DIR` or `~/.local/bin`. It does **not** edit `~/.bashrc` unless `--add-to-path` is passed — and that flag writes to `~/.bashrc` only, so zsh users must add the directory themselves. Idempotent: an existing matching version is reported, not reinstalled.

### `argocd-start` — connect and list applications

```bash
argocd-start.sh [--context <ctx>] [--kubeconfig <file>] [--namespace argocd] [--port 8080] \
  [--no-forward] [--server <url>] [--token <t> | --password <p>] [--json]
```

Starts `kubectl port-forward` to `svc/argocd-server` when the server is not answering, waits for readiness, then authenticates with `--token` (or `ARGOCD_AUTH_TOKEN`) or `--password`. It never reads Argo CD Secrets — obtain a token or password from the user or your secret store. A forwarded endpoint is only reused when the recorded forward is the process still owning it; anything else on the port is refused. `--server` is authoritative and implies `--no-forward`. Prints `argocd app list` as `-o wide` or JSON. `--stop-forward` kills the recorded forward for that context/port. On shared hosts prefer `--token`/`ARGOCD_AUTH_TOKEN`: `argocd login --password` exposes the password in the process list while it runs.

### `argocd-restart` — serve a renewed certificate

```bash
argocd-restart.sh --context <ctx> [--kubeconfig <file>] [--repo-server] [--verify-host <host>] [--dry-run] [--json]
```

Argo CD loads its server certificate from Secret `argocd-server-tls` at startup; writing a renewed certificate into the secret does not reliably hot-reload it. This restarts `deployment/argocd-server` (plus `argocd-repo-server` with `--repo-server`), waits for the rollout, and with `--verify-host` reads the live certificate over TLS and fails if it is still expired.

## Output contract

All three accept `--json`; when it is set, diagnostics go to stderr and stdout carries only the result.

- `argocd-start --json` prints the raw `argocd app list` array.
- `argocd-install` and `argocd-restart` print an object only on a successful run; on failure they exit non-zero and write the reason to stderr.

Exit codes are stable:

| Code | Meaning                               |
| ---- | ------------------------------------- |
| 0    | success                               |
| 1    | apply, rollout or verification failed |
| 2    | usage error or failed preflight       |
| 3    | aborted at the confirmation prompt    |

## Gotchas

- **Argo CD's own install is GitOps-managed.** Its version is pinned in `src/manifests/argocd/argocd/kustomization.yaml` in the k8s repos — upgrade by bumping that pin, never by applying upstream manifests by hand.
- **TLS is verified for remote servers.** `argocd-start` passes `--insecure` only for the local port-forward; a remote `--server` URL needs an explicit `--insecure` to skip verification.
- **The server certificate is not hot-reloaded.** After updating `argocd-server-tls`, run `argocd-restart --verify-host <argocd-host>`; verify the certificate actually served, never the secret alone.
- **`--context` is mandatory** on the cluster-changing scripts. They never fall back to the current context, and they refuse a context that cannot patch Deployments. All accept `--kubeconfig`; without it they use `$KUBECONFIG` or `~/.kube/config` — in a devbot project, point them at the generated kubeconfig (`devbot kube env <project>`) rather than relying on the machine default.
