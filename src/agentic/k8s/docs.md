---
title: "K8s"
description: "Kubernetes manifest linting and MCP-only cluster access — one kubectl server per cluster."
skills: ["lint-k8s", "k8s-access"]
hooks: ["lint-k8s"]
tools: ["lint-k8s"]
---

Audits Kubernetes, Kustomize, and Helm manifests with `kubeconform` (schema validation) and `kube-linter` (best practices), and exposes a project's clusters as `kctl-<cluster>` MCP servers so an agent never runs `kubectl` itself.

## How agents use it

Auto-lints on file save when editing K8s YAML files. Agents can also invoke it explicitly to validate manifests before deployment.

Cluster commands go through the MCP servers — see [Cluster access](#cluster-access).

## Cluster access

`init.sh` reads the `kubectl` node of the global config — a catalogue of
clusters — together with the project's `kubectl` list of cluster names to opt
into. It writes **two files per project**:

```
~/.kube/devbot/<project_name>-<8-hex>.yaml   the kubeconfig
~/.kube/devbot/<project_name>-<8-hex>.env    the env file (KUBECONFIG only)
```

`<8-hex>` is the first eight characters of the sha256 of the project's absolute
path, so two checkouts that share a directory name keep separate files. Neither
name is guessable — resolve them with `devbot kctl` rather than listing the
directory.

The context names come from each catalogue entry's `context` field. In the
default catalogue that is `gete-prod-ro` (read-only production) and
`gete-staging-rw` (staging); the identity lands in the `gete-agents-readonly` and
`gete-agents-writer` groups. **Do not use `~/.kube/config`** — its contexts are
SSO exec contexts that expire; these use the devbot profile.

### MCP servers — one per cluster

Every cluster that rendered becomes its own stdio MCP server, named
`kctl-<cluster>`, with a single tool:

| Server           | Tool      | Meaning                                                                                                           |
| ---------------- | --------- | ----------------------------------------------------------------------------------------------------------------- |
| `kctl-<cluster>` | `kubectl` | Run kubectl against that cluster. `args` is kubectl's argv (a string array); optional `stdin` feeds `apply -f -`. |

The server _is_ the scoping: the cluster is fixed at launch, so the tool has no
`--context` to get wrong and the server can reach nothing else. It also refuses
`--kubeconfig`, `--server`, `--cluster`, `--user`, `--token`, `--as`,
`--as-group`, `--as-uid`, `--username`, `--password`, `--proxy-url`,
`--tls-server-name`, `--client-certificate`, `--client-key`,
`--certificate-authority`, `--insecure-skip-tls-verify` and a leading
`kubectl`/`k` in `args`, plus the `kubectl config` write subcommands — the
kubeconfig is rendered, so `config set-*`/`use-context` would retarget every
later call for that cluster — and `config view --raw`, which would print its
credentials into the tool result. `config view` and `get-contexts` still work,
redacted.

Each call is executed through `devbot kctl exec <cluster>`, so the context
banner, the credential preflight and the override refusals are the same code the
CLI runs — the two cannot drift apart. The servers are published from the
**rendered** set, not the selection: a cluster the render dropped has no context
in the file, so `devbot reinit` is what adds or removes one. They are declared
enabled (not `wire_disabled`), because the module's memory makes them the only
permitted way to reach a cluster.

The runtime manifest group is `k8s-<cluster>` while the server key is
`kctl-<cluster>`: a disabled module's manifests are recognised by their
filename, so the file keeps the module's name and only the key is shortened
(`docs/create-a-module.md`). `devbot list mcps` lists the key, which is what
the agent's tool list shows.

The launcher needs `bun` (installed by `devbot install`); without it the server
reports the missing runtime in `.agents/logs/kctl-<cluster>-mcp.log` instead of
starting. A call is bounded at 120 s — a hung `watch` or `port-forward` would
otherwise outlive the client's wait and keep running — and one the operator knows
is slow can be given `KCTL_MCP_TIMEOUT_MS` in the environment that launches the
harness.

### Using it from a shell

```sh
devbot kctl env      [path]   # KUBECONFIG + current context (no credentials)
devbot kctl contexts [path]   # cluster name, context, region
devbot kctl run      [path] -- get pods -n core
devbot kctl exec     <cluster> [path] -- get pods -n core
```

`devbot kctl run` execs `kubectl --kubeconfig <file>`. The arguments after `--` are **kubectl's
own** — do not repeat the binary: `-- kubectl get ns` fails, `-- get ns` is what you want, and the
wrapper refuses the repeated form rather than letting kubectl report a plugin error.

`devbot kctl exec` takes the cluster name from the catalogue and applies that
cluster's context itself. It is what the MCP servers call, and it refuses a
caller `--context` — one cluster's entry point cannot retarget another's.

Credentials come from the
`credential_env` map in the global catalogue: each entry is exported as its key
(`AWS_ACCESS_KEY_ID`) with the value of the `${VAR}` it references (`AWS_KEY`),
and the kubeconfig's exec wrapper reads those at call time. So the **referenced**
variables — `AWS_KEY`, `AWS_SECRET` with the shipped catalogue — must be set in
the environment before the command runs; `devbot kctl env` prints which ones
your catalogue needs. The generated `.env` holds only `KUBECONFIG`, never a
credential.

The generated config is **not** merged into `~/.kube/config`. For human
inspection, point kubectl at the generated file explicitly:

```sh
devbot kctl env ~/Development/Get-e/core   # prints the KUBECONFIG path
kubectl --kubeconfig <path> --context gete-staging-rw get pods -n core
```

The files are rendered, not read live: after changing the project's `kubectl`
selection or the global catalogue, run `devbot reinit <path>`.

### Always-on instructions

Whenever the module is enabled, `init.sh` copies the module's `k8s.md` to
`<devbot_dir>/memory/active/modules/k8s.md`. It is an absolute prohibition —
never run `kubectl` in any shell, always use the `kctl-<cluster>` MCP — plus the
RBAC boundaries and the gotchas, so the agent reads the rules without them being
hand-copied into the project's `project.md`.

The file is written before the cluster render, and it survives one: it describes
the module, not the state of this machine, so a project with no selection, no
AWS or a stale credential still learns that a shell is off limits. A project
that disables the module gets no file, and `devbot reinit` clears
`active/modules/` first, so a dropped module loses it. A direct run with the
module disabled also prunes the project's kubeconfig and the emitted MCP
manifests; the harness's own aggregate (claudecode's `.mcp.json`) is rebuilt
from scratch by `devbot reinit`, since a module never writes a harness manifest.

The prohibition is stated once and enforced twice: the memory binds every
channel, and the shipped guard rules block the direct forms — `kubectl`, the
`VAR=… kubectl` prefix, `kubectl` inside a command runner, and
`devbot kctl run|exec` (see [Guards](/modules/agentic/guards)). A hook only sees
a shell command, so the guards are a backstop rather than the whole rule.
The rules match the binary's path and an environment-assignment prefix as well
as the bare name, and they reach an existing install through the `1.19.0`
config migration, since a dist config is only copied into a machine that has
none.

RBAC boundaries, what the reader and writer groups grant, and the exec
restriction are documented in the `k8s-access` skill.

## Configuration

Cluster access needs a `kubectl` node in the global config plus a `kubectl`
list of cluster names in the project; linting needs nothing. See the `kubectl`
section of [configuration](/docs/configuration) for the shape, and note that
credential values stay in the environment — the generated wrapper carries a
`${VAR}` reference, never a key.

The `profile` named there must already exist in `~/.aws/config`, and it must be
an **assumable role** profile — `role_arn` plus `credential_source =
Environment`. dev-bot does not create it, and init refuses to render when the
profile resolves to anything but an assumed-role session:

```ini
[profile devbot-agent]
role_arn = arn:aws:iam::<account-id>:role/<cluster-access-role>
credential_source = Environment
```

A profile carrying only access keys is rejected on purpose: environment
credentials win over a profile's own keys, so without a `role_arn` the agent
would silently run as the key's owner instead of the scoped cluster role.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [Docker](/module-reference) — Dockerfile authoring patterns
