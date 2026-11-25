---
date: 2026-11-25
keywords: ["docker", "compose", "extends", "dns", "nginx"]
aliases: ["network alias inheritance", "php-fpm upstream", "container name resolution"]
trigger-on: ["compose-service-naming"]
---

## Compose `extends` inherits network aliases; use the container name for a unique upstream

A network `aliases:` entry declared on a base service is copied into every service that `extends` it, so an alias added to `app` also lands on its queue workers — and a proxy resolving that alias then sends PHP requests to containers that never listen on 9000. The container name is the identity that survives, because Docker's embedded DNS resolves `<compose-project>-<service>-<index>` on a user-defined network and nothing inherits it. So point the proxy at `${PROJECT_NAME}-app-1:9000` through a variable (e.g. `PHP_FPM_UPSTREAM`) set in the project's compose, and keep a Dockerfile `ENV` default of `app:9000` so the k8s pod, which resolves `app` through a `hostAliases` entry, is unchanged. Prove it with `docker compose config --format json` (the value must land on the proxy service, not the app), `nginx -T` inside the image (default and override), and `getent hosts <project>-app-1` inside the proxy (one address, where the bare `app` returns every project's).
