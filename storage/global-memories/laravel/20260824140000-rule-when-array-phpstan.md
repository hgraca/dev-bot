---
date: 2026-08-24
keywords: ["laravel", "validation", "phpstan", "rule-when"]
trigger-on: ["rule-when-validation", "laravel-conditional-validation"]
---

## Laravel Rule::when must wrap rule objects in an array for PHPStan

`Rule::when($condition, Rule::exists('table', 'id'))` fails PHPStan (`argument.type`): the second parameter's accepted types are `array|Closure|InvokableRule|Rule|ValidationRule|string` but a bare `Rules\Exists` object is not in that union. Wrap the rule in an array: `Rule::when($ownerType === 'hotel', [Rule::exists('hotels', 'id')])`. This is also the documented form in the Laravel validation docs and works identically at runtime (empty array when the condition is false). Do not "fix" it by passing a closure that returns the rule — `Rule::when` returns the closure as-is, and the validator treats closures as attribute callbacks, so validation would silently do nothing.
