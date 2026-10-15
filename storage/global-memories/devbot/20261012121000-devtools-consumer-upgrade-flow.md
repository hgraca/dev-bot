---
date: 2026-10-12
keywords: ["devbot", "dev-tools", "composer", "release", "consumers"]
trigger-on: ["devtools-consumer-upgrade", "devtools-release"]
---

## The dev-tools release → consumer upgrade flow

Releasing `get-e/dev-tools` and bumping its consumers follows a fixed shape. Consumers resolve dev-tools from the **VCS repo** (`git@github.com:GET-E/dev-tools.git`), so the released **tag** is what they need — no Packagist. Per consumer: branch `chore/dev-tools-<version>` from `origin/main`, run `composer require --dev get-e/dev-tools:^<version>`, commit `chore(deps): upgrade dev-tools to <version>`, push, and open a PR titled the same with a body of `## Summary` ("Bump `get-e/dev-tools` from X to Y") plus `## What's in Y` (one bullet per release change, linked to the dev-tools PR). The bump changes `composer.json` (constraint), `composer.lock` (only the dev-tools entry: version, source/dist reference, support source, time, content-hash), and any managed file the DevTools plugin re-syncs — the deploy workflow when it changed in the release. Branches are deleted after merge. Verified 2026-10-12 for 0.7.7.0 → 0.7.8.0 across core, hotels-api, positioning-activities, zendesk-synchronizer, exchange-rates and audit-log.
