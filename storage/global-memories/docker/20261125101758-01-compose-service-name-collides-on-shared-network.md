---
date: 2026-11-25
keywords: ["docker", "compose", "dns", "shared-network"]
aliases: ["app alias collision", "external network", "service discovery"]
trigger-on: ["compose-service-naming"]
---

## A generic compose service name collides across projects on a shared external network

Docker's embedded DNS registers a container under its compose **service** name on every network it joins, so when several projects each have a service called `app` attached to the same external network (here `get-e-dev`), `getent hosts app` from any one of them returns every project's container and a proxy doing `fastcgi_pass app:9000` load-balances across all of them. The symptom is non-determinism that reads like an application bug: the same URL returns `200`, `404`, `500` and a `302` to a sibling project's login portal on consecutive calls, and the sibling's labels appear in your metrics. Diagnose with `docker exec <project>-nginx-1 getent hosts app` (more than one IP is the bug) and confirm the wrong-app theory by comparing a response against `php artisan tinker --execute="echo config('app.name');"`. Fix by naming each compose service uniquely (`positioning-app`) or giving each project's proxy a project-scoped network with an explicit link to its own app; to measure something deterministically without changing the project, pin the alias in the proxy's `/etc/hosts` and `nginx -s reload`, then recreate the container to revert.
