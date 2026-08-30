---
name: devbot:lint-k8s
description: "Use this skill whenever reviewing, auditing, or validating Kubernetes, Kustomize, or Helm manifests with kubeconform (schema validation) and kube-linter (best practices). Triggers on 'audit k8s', 'lint kubernetes', 'validate manifest', 'check helm chart', 'kustomize validation', or when working with K8s infrastructure-as-code — even if they do not say 'lint'."
---

# lint-k8s

Audit K8s, Kustomize, or Helm manifests using `lint-k8s` tool (wraps kubeconform + kube-linter).

## When to Use

Activate this skill whenever you are:

- Auditing or reviewing Kubernetes manifests (Deployments, Services, ConfigMaps, etc.)
- Validating Helm chart templates or values files
- Checking Kustomize overlays and bases
- Reviewing PRs that touch YAML/YML files under `k8s/`, `charts/`, `helm/`, `infra/`, or similar paths
- Asked to "validate", "audit", "lint", or "check" K8s configurations

## Tool: `devbot:lint-k8s`

You have a built-in custom tool `devbot:lint-k8s`. It runs both kubeconform and kube-linter and returns a combined JSON report.

### How to invoke it

Use the tool call mechanism — call `devbot:lint-k8s` with these arguments:

| Arg      | Required | Description                                          |
| -------- | -------- | ---------------------------------------------------- |
| `path`   | Yes      | File or directory path containing YAML/YML manifests |
| `schema` | No       | kubeconform schema location (default: auto-detect)   |
| `format` | No       | `"json"` (default) or `"markdown"`                   |

**Tool call pattern**:

```
lint-k8s(path: "<file-or-dir>")
lint-k8s(path: "<file-or-dir>", schema: "kubernetes")
lint-k8s(path: "<file-or-dir>", format: "markdown")
```

### What it checks

| Tool            | What                                                                                        | Severity                         |
| --------------- | ------------------------------------------------------------------------------------------- | -------------------------------- |
| **kubeconform** | Schema validation — invalid fields, wrong types, missing required keys                      | Error (schema invalid = broken)  |
| **kube-linter** | Best practices — security contexts, resource limits, privileged containers, deprecated APIs | Warning/Error (depends on check) |

### Reading the result

The tool returns a JSON object:

```json
{
    "success": true,
    "path": "/abs/path/to/manifests",
    "kubeconform": {
        "valid": true,
        "summary": "...",
        "results": [{ "filename": "...", "status": "valid|invalid|error", "message": "..." }]
    },
    "kubelinter": {
        "valid": true,
        "summary": "N violation(s) across M file(s)",
        "violations": 0,
        "report": {/* full kube-linter JSON report */}
    }
}
```

**kubeconform failures** (`valid: false`) = hard errors. Manifest rejected by API server. Fix immediately.

**kube-linter violations** (`violations > 0`) = best-practice recommendations. Review each:

- Security-related (privileged, hostNetwork, capabilities) — fix always
- Resource-related (missing limits/requests) — fix unless intended
- Style-related (latest tag, deprecated API) — fix in most cases

## Workflow

1. **Identify** all YAML/YML/JSON manifest files under the target path
2. **Invoke** `lint-k8s(path: "<target-path>")` using your built-in tool
3. **Parse** the JSON result:
    - Report kubeconform errors with filename + message
    - Report kube-linter violations grouped by severity (from `kubelinter.report`)
4. **Fix** each finding or explain why it is acceptable
5. **Re-run** `devbot:lint-k8s` after fixes — confirm `success: true` and zero failures

## Testing the hook

The `lint-k8s` hook fires when a `.yaml`/`.yml` file containing a Kubernetes manifest (`apiVersion: …` and `kind: …`) is edited. A bundled example manifest lives at `assets/example-deployment.yaml` (next to this SKILL.md). To verify the hook end-to-end:

1. Copy it into the project: `cp assets/example-deployment.yaml ./example-deployment.yaml`
2. Edit it (e.g. bump `replicas` or change the image tag)
3. The hook runs kubeconform + kube-linter automatically and logs to `.agents/logs/lint-k8s.log`

To exercise the tool directly without the hook, call `lint-k8s(path: "./example-deployment.yaml")`.
