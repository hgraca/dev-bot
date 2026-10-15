---
date: 2026-10-15
keywords: ["composer", "composer.lock", "content-hash", "composer-patches"]
trigger-on: ["composer-lock-content-hash", "composer-patches"]
---

## composer.lock's content-hash is an md5 of a JSON projection of composer.json — recompute it offline when you can't re-resolve

`composer.lock`'s `content-hash` is **not** sha256 — it is 32 hex chars, `hash('md5', JsonFile::encode($relevantContent, 0))`, where `JsonFile::encode($data, 0)` is plain `json_encode($data, 0)`. `$relevantContent` keeps only these `composer.json` keys, merged in this order then `ksort`ed: `name`, `version`, `require`, `require-dev`, `conflict`, `replace`, `provide`, `minimum-stability`, `prefer-stable`, `repositories`, `extra`, plus `config.platform` when present.

So any edit to `composer.json` — even deleting an `extra.patches` block — invalidates the hash and `composer validate` reports the lock as out of date. `composer update --lock` normally fixes it, but it re-resolves and needs network access to **every** repository, including private VCS repos (`git@github.com:org/repo`) that a bare container cannot clone (no ssh). When re-resolution is impossible, recompute the hash directly:

```php
$c = json_decode(file_get_contents('composer.json'), true);
$keys = ['name','version','require','require-dev','conflict','replace','provide','minimum-stability','prefer-stable','repositories','extra'];
$r = [];
foreach (array_intersect($keys, array_keys($c)) as $k) { $r[$k] = $c[$k]; }
if (isset($c['config']['platform'])) { $r['config']['platform'] = $c['config']['platform']; }
ksort($r);
echo hash('md5', json_encode($r, 0)), PHP_EOL;
```

**Validate against the current on-disk hash before trusting the output** (it must reproduce the old value for the unmodified file), then write the new value into `composer.lock` and confirm with `composer validate`.

Related: `cweagans/composer-patches` **re-creates** `patches.lock.json` even when no patches remain, as `{"_hash": "...", "patches": []}`. Commit that regenerated empty file instead of deleting it, so `composer install` does not leave the tree dirty.
