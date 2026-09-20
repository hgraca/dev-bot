---
date: 2026-09-18
keywords: ["k8s", "kustomize", "patch", "sidecar"]
trigger-on: ["kustomize-patch", "kustomize-target-name", "kustomize-envFrom"]
---

## Kustomize patch `target.name` is a full match — a `-.*` suffix regex excludes the base deployment

A patch targeting `kind: Deployment, name: positioning-marabu-.*` matches the worker deployments (`positioning-marabu-mb-high-worker`, `positioning-marabu-kafka-consumer`, …) but NOT `positioning-marabu` itself, because the regex demands a trailing `-...`. In a web Deployment that runs php-fpm as an `initContainer` sidecar and nginx as `containers[0]`, that pattern injects configuration into the workers and the sidecar only, silently leaving nginx without the variables its envsubst'd config requires — which then crash-loops the container at startup. Render with `kubectl kustomize <dir>` and diff against a baseline before and after, because `op: add` on `/env` REPLACES the list rather than appending to it, so an over-broad target would wipe the workers' entire environment.
