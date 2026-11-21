---
date: 2026-11-18
keywords: ["keycloak", "theme", "cache", "loginTheme", "accountTheme"]
trigger-on: ["keycloak-theme"]
---

## A Keycloak theme change needs three separate things defeated

Editing a theme's CSS or templates is not enough to see the change, and there are three independent layers. First, the realm pointer: `loginTheme`/`accountTheme` are realm attributes, and `--import-realm` only applies them to a realm that does not yet exist — an existing realm keeps whatever it had, so it must be set through the admin API (`kcadm.sh update realms/<realm> -s loginTheme=<name> -s accountTheme=<name>`), which needs a live server and the bootstrap admin. Second, the process: Keycloak caches resolved themes in memory at startup, so files that appear in `/opt/keycloak/themes/<name>/` after the pod started are invisible until it restarts — stamp the deployment's pod template with a hash of the theme content and roll it (a ConfigMap volume updates its files in place, which makes the staleness look impossible). Third, the browser: theme resources are served with `Cache-Control: max-age=2592000`, so a returning visitor keeps last month's stylesheet and a correctly applied theme looks unchanged; `KC_SPI_THEME_STATIC_MAX_AGE=-1` turns that off, after which the same URL answers `cache-control: no-cache`. Diagnose in that order — `curl -sI <resource>` shows which cache is lying, and `kcadm get realms/<realm> --fields loginTheme,accountTheme` shows the pointer.
