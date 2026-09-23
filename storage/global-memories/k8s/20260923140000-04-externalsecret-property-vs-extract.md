---
date: 2026-09-23
keywords: ["k8s", "external-secrets", "secrets-manager", "eso"]
trigger-on: ["external-secret-projection", "eso-remote-ref"]
---

## External Secrets: `data[].remoteRef.property` fetches one key — `dataFrom.extract` copies *all* of them

When projecting a single value out of an AWS Secrets Manager secret that holds many, the choice of field is a security decision, not a style one. `data[].remoteRef.property` with a JSON path fetches exactly that one key. `dataFrom.extract` fetches **every** key in the secret and lands them all in the target Kubernetes Secret — so pointing it at an application's shared secret (which typically also carries database passwords, API tokens and mail credentials) silently copies that entire credential set into whatever namespace the ExternalSecret lives in, including a low-trust infrastructure namespace like an observability one. Use `extract` only when you genuinely want the whole secret. Two further ESO details that matter in practice: a `SecretStore` is **namespaced**, so a store named `main-store` in namespace `default` cannot be referenced from another namespace — that namespace needs its own `SecretStore` (the AWS auth lives on the controller's IRSA role, so the store itself carries no credentials); and `spec.target.template.data` composes new values with Go templating over the fetched entries, which is how a host-only secret becomes a full connection URI (`REDIS_ADDR: "redis://{{ .REDIS_HOST }}:6379"`) and keeps the endpoint single-sourced in the secret store instead of duplicated into git. Note the template's default `mergePolicy: Merge` keeps the originally-fetched key in the target Secret alongside the templated one.
