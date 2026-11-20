# Kubernetes access — MCP only

**NEVER run `kubectl` in any shell. Not once, not read-only, not "just to check".**

This project's cluster access exists only through the `kctl-<key>` MCP
servers this module registers — one per catalogue entry, named after its key. The `kubectl` binary on this machine is off limits to an agent:

- the bash tool, every PTY session, scripts, Makefiles, CI files, `ssh host …`,
  `docker exec … kubectl`, `KUBECONFIG=… kubectl` — all prohibited;
- `k` is the same client, so it is just as prohibited as `kubectl`;
- `devbot kctl run` and `devbot kctl exec` run kubectl too — they are the
  human's CLI, not an agent escape hatch, and they are blocked;
- `~/.kube/config` is not an alternative: its contexts are SSO exec contexts
  that expire, and they are not this project's access.

The shipped guard rules block the direct forms: `kubectl`, the
`VAR=… kubectl` prefix, `kubectl` inside a command runner (`bash -c`, `xargs`,
`ssh`, `docker exec`), and `devbot kctl run|exec`. They are a backstop, not the
whole rule — a hook sees a shell command, not what a script or a Makefile
recipe does, so the prohibition above is the one that binds.

The reason is not stylistic. Each project gets its own generated kubeconfig
(`~/.kube/devbot/<project_name>-<8-hex>.yaml`) holding only the clusters it
selected, reached with the devbot AWS profile. Hand-running `kubectl` bypasses
that boundary, and an answer read from the wrong cluster gets reported as the
right one.

## Use the MCP servers instead

Each cluster the project selected appears as its own MCP server, named after the
catalogue key — `kctl-<key>`.

| Server       | One tool  | Target                      |
| ------------ | --------- | --------------------------- |
| `kctl-<key>` | `kubectl` | that cluster's context only |

The tool takes kubectl's own argv:

```jsonc
// kctl-gete-dev → kubectl
{ "args": ["get", "pods", "-n", "core"] }
{ "args": ["logs", "-n", "core", "deploy/transfers", "--tail=100"] }
{ "args": ["get", "applications", "-n", "argocd"] }
{ "args": ["apply", "-f", "-"], "stdin": "…manifest yaml…" }
```

Rules for calling it:

- **One element per argument.** `["get","pods","-n","core"]`, not
  `["get pods -n core"]` — no shell parses it, so quoting is never stripped.
- **No leading `kubectl`.** The server already runs it; a leading `kubectl` or
  `k` is refused.
- **No `--context`, `--kubeconfig`, `--server`, `--cluster`, `--user`,
  `--token`, `--as`, `--as-group`, `--as-uid`, `--username`, `--password`,
  `--proxy-url`, `--tls-server-name`, `--client-*`,
  `--certificate-authority`, `--insecure-skip-tls-verify`.** The server owns
  the target and refuses them.
- **No `kubectl config` write subcommands** (`set*`, `unset`, `use-context`,
  `delete-*`, `rename-context`), and **no `config --raw`**: the first rewrites
  the generated kubeconfig (retargeting every later call for this cluster), the
  second prints its credentials into your context. `config view` and
  `get-contexts` still work, redacted.
- **Use the server named for the cluster you mean.** Reaching staging through
  `kctl-gete` is not possible — that is the point, not a limitation to work
  around.

If no `kctl-<key>` server is available, this project has no cluster access.
Report that and ask the human to run `devbot reinit <project>`; never fall back
to `kubectl`.

The `devbot kctl` command exists for the **human** and for maintenance.
`env` and `contexts` only print the kubeconfig and the cluster list, and an
agent may use them for diagnostics. `run` and `exec` are shell commands that run
kubectl, so they are forbidden here exactly like kubectl itself — and the guard
blocks them.

## What the identity can do

`kubectl auth whoami` (through the MCP) shows the groups the credentials land in:

| Group                  | Grants                                                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `gete-agents-readonly` | cluster-wide `get/list/watch` — including `pods/log` — with **no** secrets, exec, port-forward or token creation |
| `gete-agents-writer`   | staging only: create/update/patch/delete workloads in the **`default`** namespace                                |

Consequences worth remembering:

- `pods/exec` is denied by design. To inspect a datastore, use the `datasources`
  module or the SigNoz metrics rather than trying to exec into the pod.
- The writer Role is namespaced to `default`. `core`, `kube-system`, `argocd` and
  `otel-collector` are read-only even on staging.
- No secrets are readable — never attempt `get secret`, and never ask for one to
  be added to the role.

## Gotchas

- **After changing `.devbot.project.jsonc` or the global `kubectl` catalogue, run
  `devbot reinit <path>`.** The kubeconfig is rendered, not read live, and the
  MCP servers are published from the rendered set — a stale project lists the
  previous selection until it is reinitialised.
- **The default context is chosen by project name**, so `k8s-gete-dev` opens on
  `gete-staging-rw` and `k8s-gete` on `gete-prod-ro`. Through the MCP this is
  implicit: the server's cluster decides its context.
- **Production is read-only.** There is no writable production context; manifest
  changes go through the GitOps repo (`k8s-gete`) and ArgoCD.
- **Do not apply manifests on staging** unless the task says so — staging is
  ArgoCD-managed from `k8s-gete-dev`, and an imperative apply is reverted on the
  next sync.
