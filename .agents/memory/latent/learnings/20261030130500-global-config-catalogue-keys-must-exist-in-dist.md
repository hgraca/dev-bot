---
date: 2026-10-30
keywords: ["reconcile_global_config", "dist", "aws_connections", "kubectl", "global-config"]
aliases: ["config key disappears on update", "update deletes aws_connections"]
---

# A global-only catalogue must be declared in the dist, or `update` deletes it

## The trap

`src/_shared/reconcile_global_config.py` aligns the runtime `.devbot.global.jsonc`
with the shipped `.devbot.global.dist.jsonc` by **top-level key name**: it adds
each dist key the runtime lacks and **removes each runtime key the dist lacks**.
Nested objects are opaque (except the additive `external_modules` merge), so
only the key's presence matters — its value is never compared.

Consequence: a global-only catalogue that a machine fills in but the dist does
not mention is destroyed on the next `devbot update`, silently and without a
backup. `aws_connections` was exactly that — present in the live config, absent
from the dist — so any machine with declared AWS role connections would have
lost them. `kubectl` escaped it only because the dist already shipped
`"kubectl": {}`.

## The rule

Every global-only catalogue belongs in the dist as an empty default plus a
commented example: `datasources`, `kubectl`, `aws_connections`,
`external_modules`. Empty is safe — an empty catalogue means "nothing
configured", and modules already handle that (k8s init skips, aws up skips).

## How to prove it before shipping a dist change

Run the reconciler against a **copy** of the live config, never the live file:

```sh
cp dev-bot/.devbot.global.jsonc /tmp/rt.jsonc
python3 dev-bot/src/_shared/reconcile_global_config.py \
  dev-bot/.devbot.global.dist.jsonc /tmp/rt.jsonc
```

`NOCHANGE` is the healthy answer; `REMOVED: <key>` names a key the dist dropped.
Regression coverage lives in `src/_shared/tests/reconcile_global_config_tests.bats`
("shipped dist keeps the kubectl and aws_connections catalogues").
