---
date: 2026-09-02
keywords: ["php", "curl", "curl_init", "TypeError"]
trigger-on: ["php-curl-init-false"]
---

## `curl_init()` can return `false` — a `TypeError` escapes `catch (Exception)` wrappers

`curl_init($url)` returns `false` for invalid URLs (or when ext-curl is degraded); passing that straight into `curl_setopt_array($curl, ...)` throws a `TypeError` — an `Error`, not an `Exception`. Code that wraps the fetch in `try { ... } catch (Exception $e)` to map failures into a domain exception (e.g. a retryable fetch error) will NOT catch it, producing an unhandled fatal instead of the intended failure path. Check the handle immediately after `curl_init`: `if ($curl === false) { throw new Exception(...); }` so the existing wrapper handles it.
