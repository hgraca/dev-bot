---
date: 2026-10-07
keywords: ["k8s", "cronjob", "schedule:run", "laravel", "message-bus"]
aliases: ["scheduled commands never run", "missing schedule:run cronjob", "bus metrics dark"]
trigger-on: ["laravel-scheduled-commands-in-k8s", "message-bus-metrics-export"]
---

## A Laravel app's scheduled commands run only if a `schedule:run` CronJob exists

Registering a command on the Laravel scheduler — an app `Kernel::schedule()`, or a package that
schedules itself (e.g. `get-e/message-bus` 0.17.22 registers `msg-bus:metrics:export` on
`* * * * *` by default) — does nothing on its own in Kubernetes: the schedule fires only when a pod
runs `php artisan schedule:run` on a timer. A deployment with no such CronJob (and no
`IS_LARAVEL_SCHEDULER` container) silently executes **none** of its scheduled commands. The
message-bus metrics export then simply no-ops and the `message_bus.*` metrics stay absent, with no
error anywhere — the symptom is "metrics missing in this environment but present in another". Before
suspecting the package, check for a per-minute `schedule:run` CronJob: the GET-E pattern is a
`* * * * *` CronJob with `concurrencyPolicy: Forbid`, the app secret + the OTEL configMap in
`envFrom`, and the service's own ServiceAccount. Adding one also starts every other scheduled task
the app defines (e.g. a daily metadata refresh) — a real behaviour change beyond the metrics.
