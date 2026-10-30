---
date: 2026-10-27
keywords: ["docker", "compose", "nginx", "fastcgi", "dev-prod-config"]
trigger-on: ["compose-service-rename", "shared-nginx-config"]
---

## One nginx config shared by dev and prod breaks when a compose service is renamed

A repo that bakes `.docker/php.conf` into its production nginx image and also mounts that same file into a local nginx container ties the two environments to one `fastcgi_pass` hostname. Renaming the dev compose service to match a tooling convention (dev-tools' Makefile expects a service called `app`) then breaks production, whose config resolves the PHP sidecar by its k8s hostname — and nothing in CI builds the prod nginx image, so the breakage ships silent.

Keep the shared file on the hostname production needs and make dev resolve it: give the dev service a network alias,

```yaml
services:
  app:
    networks:
      default:
        aliases:
          - positioning-flights-php-fpm
```

That keeps `fastcgi_pass positioning-flights-php-fpm:9000` valid in both places. The alternative — a second nginx config for dev — works but forks the routing rules and drifts.
