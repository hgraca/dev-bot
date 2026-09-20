---
date: 2026-08-31
keywords: ["php", "php-cs-fixer", "mb_str_functions", "strlen", "curl"]
trigger-on: ["php-cs-fixer-strlen-byte-count"]
---

## PHP-CS-Fixer `mb_str_functions` silently reverts `strlen` where byte counts are required

`GetE\DevTools\Php\PhpCsFixer\PhpCsFixerDefaultConfig` (get-e/dev-tools default) enables `'mb_str_functions' => true`, which rewrites every `strlen(...)` to `mb_strlen(...)` on each `php-cs-fixer fix` run — silently, and the fixer cache makes it easy to miss (a hand-written `strlen` fix gets reverted the next time the fixer runs over the file, with no diff at commit time). This is fatal where byte counts are required, e.g. a cURL `CURLOPT_WRITEFUNCTION` callback must return the number of **bytes** consumed — `mb_strlen` returns character count, so multi-byte payloads abort with `CURLE_WRITE_ERROR` and the size-bound check under-counts.

Fix: pass the override in the project's `.php-cs-fixer.php`:

```php
return PhpCsFixerDefaultConfig::create(
    $finder,
    rulesOverrides: ['mb_str_functions' => false],
);
```

(hotels-api's SAML adapter hit the same trap; the rule itself documents the risk "relying on the string byte size"). After adding the override, verify the intended `strlen` survives a fixer run: `grep` the call sites after `php-cs-fixer fix`.
