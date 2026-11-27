---
date: 2026-11-27
keywords: ["php", "money", "php-overlay", "minor-units"]
trigger-on: ["php-overlay-money", "money-construction"]
---

## `Money` treats a whole-number argument as minor units

`new Money(100, Currency::EUR())` is **1.00 EUR**, not 100.00: the constructor calls
`BrickMoney::ofMinor()` whenever the amount has no decimal part, so an int means cents. In a test
fixture this silently produces numbers two orders of magnitude out and the assertion fails with a
confusing `'1.00' !== '100.00'`. Use a decimal string (`'100.00'`) or `new Number(100)` for whole
major units, and reserve bare ints for cases where minor units are genuinely meant.

Related trap in the same class: `Money` throws `CurrencyDecimalsExceededException` when the amount
carries more decimals than the currency allows, so a `0.05` tolerance cannot be stored as `Money` in
a zero-decimal currency (JPY). Keep a currency-agnostic decimal as a plain value.
