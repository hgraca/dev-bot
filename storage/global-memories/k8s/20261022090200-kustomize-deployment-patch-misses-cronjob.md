---
date: 2026-10-22
keywords: ["k8s", "kustomize", "cronjob", "k8sattributes"]
aliases: ["cronjob not instrumented", "otel env on cronjob", "service.name from pod label"]
---

## A kustomize patch scoped to `kind: Deployment` leaves its sibling CronJob dark

A service kustomization that injects OTel wiring with `target: {kind: Deployment}` (and `name: <service>-api`) silently skips every other workload in the same directory. Concretely: `exchange-rates` had the `otel-env-<svc>` configMap appended to the Deployment's php-fpm sidecar, while the sibling `exchange-rates-update-rates` **CronJob** — same kustomization, different `kind` — received only its secret, so it emitted **zero spans** for months. Nothing errors; the CronJob simply has no `OTEL_PHP_AUTOLOAD_ENABLED`, so no SDK, no spans, and any `Cron job missed` rule keyed on its run span can never match (an `alertOnAbsent` rule on it fires forever instead).

Two things are needed, and the second is easy to miss. Add the configMap to the CronJob's own pod template — for a CronJob the env path is `/spec/jobTemplate/spec/template/spec/containers/0/envFrom/-`, note the extra `/template/` compared with a Deployment. Then also add the **`OTEL_SERVICE_NAME` pod label**, because a collector `k8sattributes` mapping with `tag_name: service.name / key: OTEL_SERVICE_NAME / from: pod` derives `service.name` from the pod label, not from the SDK's resource. A pod without that label produces logs and spans with no `service.name`, and a prod log pipeline that drops unlabelled records discards them entirely — so the CronJob appeared to "emit nothing" even for stderr logs it had always written.

Verification without waiting for the schedule: `kubectl create job --from=cronjob/<name> <probe>` on a non-prod cluster, then check the run span (e.g. `Command <cmd>` for a Laravel artisan command) and its resource attributes. Delete the probe Job afterwards — the collector names `k8s.cronjob.name` after the standalone Job, so it is visibly not the real one.
