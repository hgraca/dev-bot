---
date: 2026-11-15
keywords: ["decap", "cms", "media_folder", "forgejo"]
aliases: ["Error loading the CMS configuration", "config must have required property media_folder", "collection list never renders"]
trigger-on: ["decap-config", "decap-cms"]
---

## Decap CMS will not load a config that omits `media_folder`

Decap validates its config against a schema at start-up and shows only "Error loading the CMS configuration" with `config must have required property 'media_folder'`, `'media_library'` and `config must match a schema in anyOf`. The collection list never renders, so any assertion that it does fails while the rest of the site works — the failure looks like an auth or network problem and is neither. `media_folder` and `public_folder` must be declared at the top level even when no collection has an image or file field. For an Astro site served from `dist/`, `media_folder: public/images` with `public_folder: /images` is correct. The fastest tell is a working sibling config: diff the two when one CMS loads and another does not.
