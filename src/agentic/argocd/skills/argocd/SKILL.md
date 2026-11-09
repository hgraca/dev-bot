---
name: devbot:argocd
description: "Use when operating an Argo CD installation — installing the CLI, connecting to a cluster, upgrading Argo CD, or rotating its TLS certificate."
---

# Argo CD

Four scripts for operating an Argo CD installation: install the CLI, connect to a cluster, upgrade in place, and restart the server after a certificate rotation. Each is runnable directly (human) and exposed as a `devbot-tools` MCP tool (agent).

## When to Use

| Situation                                            | Tool             |
| ---------------------------------------------------- | ---------------- |
| The `argocd` CLI is missing or outdated              | `argocd-install` |
| You need application status from a cluster           | `argocd-start`   |
| Argo CD itself must be upgraded                      | `argocd-upgrade` |
| A renewed server certificate is not being served yet | `argocd-restart` |

Anything that changes a cluster needs a kube context that can authenticate there. `argocd-upgrade` and `argocd-restart` additionally need permission to patch CRDs and Deployments respectively — a read-only context is refused by the preflight, not by a failed apply.

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

### `argocd-upgrade` — upgrade in place

```bash
argocd-upgrade.sh <version> --context <ctx> [--kubeconfig <file>] [--dry-run] [--yes] \
  [--rollback | --allow-downgrade] [--allow-degraded] [--settle <s>] [--json]
```

Applies `https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/[ha/]install.yaml` with `--server-side --force-conflicts --field-manager=argocd-upgrade`. Before that it backs up the namespace's ConfigMaps, workloads, Applications/ApplicationSets and the three CRDs into a 0700 directory — **Secrets are never backed up**, and the credential-bearing ConfigMap keys (`dex.config`, `repositories`, `repository.credentials`) are redacted — and after it verifies every `argocd-*` workload's image against the manifest, `argocd-cm` keys, `.data.url`, `ComparisonError` conditions and the application inventory. Non-HA vs HA is auto-detected from the presence of `argocd-redis-ha-haproxy`.

- **`--dry-run`** validates against the live API server and changes nothing.
- **`--yes` is required non-interactively** — without it the script refuses rather than silently skipping confirmation.
- **`--settle <seconds>`** controls the wait before the diff check (default 60, `0` skips).
- **`--rollback`/`--allow-downgrade`** permit an older target; the older manifests re-apply older CRDs, which is not a clean revert.

### `argocd-restart` — serve a renewed certificate

```bash
argocd-restart.sh --context <ctx> [--kubeconfig <file>] [--repo-server] [--verify-host <host>] [--dry-run] [--json]
```

Argo CD loads its server certificate from Secret `argocd-server-tls` at startup; writing a renewed certificate into the secret does not reliably hot-reload it. This restarts `deployment/argocd-server` (plus `argocd-repo-server` with `--repo-server`), waits for the rollout, and with `--verify-host` reads the live certificate over TLS and fails if it is still expired.

## Output contract

All four accept `--json`; when it is set, diagnostics go to stderr and stdout carries only the result.

- `argocd-start --json` prints the raw `argocd app list` array.
- `argocd-upgrade --json` always prints one envelope object — including on preflight and verification failures — with `status`, `from`, `to`, `backup`, `applied`, `problems` and `exitCode`.
- `argocd-install` and `argocd-restart` print an object only on a successful run; on failure they exit non-zero and write the reason to stderr.

Exit codes are stable:

| Code | Meaning                               |
| ---- | ------------------------------------- |
| 0    | success                               |
| 1    | apply, rollout or verification failed |
| 2    | usage error or failed preflight       |
| 3    | aborted at the confirmation prompt    |

## Gotchas

- **Argo CD 3.6 changed diffing.** With `ServerSideApply=true`, `ServerSideDiff` is now implied, so applications that use it (agentgateway, keda, …) can surface a `ComparisonError`. The upgrade reports it; opt out per Application with `argocd.argoproj.io/compare-options: ServerSideDiff=false`.
- **Treat the upgrade as a cluster-admin operation.** It checks the apply permission set (CRDs, cluster RBAC, and create/patch on the namespaced resources) before touching anything, and refuses rather than half-applying.
- **TLS is verified for remote servers.** `argocd-start` passes `--insecure` only for the local port-forward; a remote `--server` URL needs an explicit `--insecure` to skip verification.
- **The server certificate is not hot-reloaded.** After updating `argocd-server-tls`, run `argocd-restart --verify-host <argocd-host>`; verify the certificate actually served, never the secret alone.
- **`--context` is mandatory** on the cluster-changing scripts. They never fall back to the current context, and they refuse a context that cannot patch CRDs/Deployments. All three also accept `--kubeconfig`; without it they use `$KUBECONFIG` or `~/.kube/config` — in a devbot project, point them at the generated kubeconfig (`devbot kube env <project>`) rather than relying on the machine default.
- **Prod is usually read-only** to the agent identity. Expect `argocd-upgrade` to reach the CRD preflight and stop there; the script is built to be handed to a human with cluster-admin.
