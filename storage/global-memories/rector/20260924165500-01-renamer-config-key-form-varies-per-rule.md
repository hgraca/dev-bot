---
date: 2026-09-24
keywords: ["rector", "renaming", "configuration", "value-object"]
trigger-on: ["rector-rename-config-key-form"]
---

## Rector's renamer config key form differs per rule

The shape of the configuration a renaming rule takes is not uniform, and getting
it wrong fails *silently* or *fatally* depending on the rule. `RenameFunctionRector`
takes a map whose **keys and values must be the fully-qualified names** —
`['Demo\oldHelper' => 'Demo\newHelper']`; a bare `'oldHelper'` key matches nothing
at all and reports zero changed files, which reads as "already renamed".
`RenameConstantRector` takes a map too but **rejects a qualified name outright**,
failing the whole run with `"Demo\DEMO_LIMIT" is not a valid constant name` — its
keys must be bare. The call/property rules take value objects instead
(`MethodCallRename(class, old, new)`, `RenameProperty`), where the class is
configured separately from the member name. Verified against Rector 2.6.7 by
running each form and diffing the result, including a config carrying both key
forms at once to see which one fires. Always confirm the key form by running the
rule on a fixture before trusting a rule's documented example.
