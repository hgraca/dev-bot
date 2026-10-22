---
date: 2026-10-22
keywords: ["php", "carbon", "date-validation", "createfromformat", "artisan-command"]
---

## Carbon::createFromFormat accepts invalid calendar dates and unpadded parts

`Carbon::createFromFormat('Y-m-d', $value)` is not a strict date validator: it normalises calendar overflows (`2025-02-30` becomes `2025-03-02`) and accepts non-zero-padded components (`2025-7-2`). It also keeps the current time-of-day unless the format is prefixed with `!`, so two values meant to be the same date can compare as different instants — and a value parsed across a midnight rollover can even compare as reversed.

Two guards are needed when the input must be a real `Y-m-d` date:

```php
$date = Carbon::createFromFormat('!Y-m-d', $value); // '!' zeroes the time-of-day
if ($date === null || $date->format('Y-m-d') !== $value) {
    return null; // rejects overflow and unpadded input
}
```

`createFromFormat` is typed `Carbon|null` and throws `Carbon\Exceptions\InvalidFormatException` on malformed input, so both the null check and a `catch` are required — for static analysis as much as for runtime.
