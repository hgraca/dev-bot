---
date: 2026-10-05
keywords: ["php", "composer", "message-bus", "vcs-dependency", "versioning"]
aliases: ["get-e/message-bus latest version", "message-bus tag scheme"]
trigger-on: ["bump-message-bus-version", "composer-vcs-dependency"]
---

## `get-e/message-bus`'s newest tag is on the `0.17.x` line — do not trust a version sort

The `get-e/message-bus` VCS repo also carries `5.5.0`…`2.x` tags, but those date from 2025-07; the active line is `0.17.x`, whose newest tag is `0.17.19.0` (2026-10-02). Git's version sort puts `5.5.0` first and would mislead a "bump to latest" into either a nonsense constraint or a refusal to move (`^0.17.16.1` only allows `<0.18`). Confirm the live line by tag creation date (`git for-each-ref --sort=-creatordate refs/tags`, not `--sort=-v:refname`), then `composer require get-e/message-bus:^<newest-0.17-tag>`.
