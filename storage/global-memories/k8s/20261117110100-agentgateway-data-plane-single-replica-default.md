---
date: 2026-11-17
keywords: ["k8s", "agentgateway", "gateway-api", "replicas", "availability"]
aliases: ["agw single pod", "AgentgatewayParameters", "gateway proxy replicas"]
trigger-on: ["agentgateway-gateway", "ingress-availability"]
---

## agentgateway runs its data plane as a single pod until an AgentgatewayParameters says otherwise

A `Gateway` with `gatewayClassName: agentgateway` gives you **no** way to set the proxy replica count, and the controller's default is **one** pod. Nothing in the Gateway object hints at it, so an ingress that fronts every hostname of a platform can sit on a single pod for months: any node drain, rollout or OOM on that pod is a full outage, and it looks like a healthy `1/1 Running` whenever you check.

Replicas and a PodDisruptionBudget live in a separate CR, referenced from the Gateway:

```yaml
# Gateway
spec:
  infrastructure:
    parametersRef: { group: agentgateway.dev, kind: AgentgatewayParameters, name: agw-params }
---
# AgentgatewayParameters
spec:
  deployment:
    spec:
      replicas: 2
  podDisruptionBudget:
    spec:
      minAvailable: 1
```

`spec.deployment.spec` is merged into the generated Deployment's spec with strategic-merge semantics, so `replicas` there behaves as expected. Under ArgoCD, give the parameters a **lower sync-wave** (`"-1"`) than the Gateway so the CR exists before the reference is applied. Verify with `kubectl get deploy agw -n <ns>` reporting 2/2 on different nodes and `kubectl get pdb agw` showing minAvailable 1.
