---
date: 2026-08-06
keywords: ["otel", "json_parser", "php", "namespace", "backslash"]
trigger-on: ["php-namespace-backslash", "fqcn-json-parse"]
---

## Normalize PHP namespace backslashes before json_parser to prevent FQCN corruption

Lenient JSON parsers (including stanza's `json_parser`) strip unescaped backslashes from JSON strings. PHP FQCNs like `App\Modules\BookingDotCom` get silently mangled to `AppModulesBookingDotCom` during `json_parser` processing. The fix: run `replace_all(body, "\\", ".")` on the raw body as an `add` operator BEFORE `json-parser`. This converts `App\Modules\Foo::bar()` to `App.Modules.Foo::bar()` — dots are valid JSON and readable. `::` separators are untouched. Place immediately before `json-parser` in the filelog operator chain:

```yaml
- id: normalize-php-namespaces
  type: add
  field: body
  value: 'EXPR(replace_all(body, "\\", "."))'
```
