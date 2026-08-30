---
layout: page
title: K8s Lint
description: Kubernetes manifest linting.
nav_section: docs
---

Audits Kubernetes, Kustomize, and Helm manifests with `kubeconform` (schema validation) and `kube-linter` (best practices).

## How agents use it

Auto-lints on file save when editing K8s YAML files. Agents can also invoke it explicitly to validate manifests before deployment.

## See also

- [Docker](/module-reference) — Dockerfile authoring patterns
