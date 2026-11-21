---
date: 2026-11-18
keywords: ["k8s", "configmap", "volume", "items", "theme"]
trigger-on: ["configmap-volume-directory"]
---

## A flat ConfigMap can mount as a directory tree through `items` paths

When a program reads a theme, plugin or template as a directory (`<theme>/<type>/theme.properties`, `resources/css/*.css`), a ConfigMap's flat keys look unusable — `--from-file` keys are basenames, so nesting is lost. A volume's `items` list fixes it: each entry's `path` may contain slashes and is materialised relative to the mount, so `{key: login.properties, path: login/theme.properties}` plus `{key: login.css, path: login/resources/css/kosmos.css}` reconstructs the tree from flat keys. The same key can be mapped to several paths, which is how one generated `tokens.css` and one script serve two theme types without duplicating content into the ConfigMap. Give the keys type-prefixed names (`login.properties`, `account.properties`) rather than the natural filename, or two files that are both `theme.properties` collide on one key. The whole ConfigMap is capped at 1 MiB, so this suits generated CSS and small templates; anything bigger wants an image. The mount is read-only and updates in place, but a program that caches what it reads at startup still needs a restart — the volume being current is not proof the process is.
