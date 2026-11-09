---
date: 2026-11-09
keywords: ["php", "php-cs-fixer", "ordered_class_elements", "phpunit"]
aliases: ["ordered_class_elements tearDown", "CS dry run test method order"]
---

## php-cs-fixer `ordered_class_elements` puts PHPUnit lifecycle methods before public tests

Appending a `tearDown()` (or `setUp()`) after the public test methods fails php-cs-fixer's
`ordered_class_elements` fixer, which is part of the default ruleset used by GetE projects: the
`CS Dry Run` job reports each file as `(ordered_class_elements)` and the diff moves the method up.
The configured order places `use_trait`, constants, properties, `construct`, `destruct`, magic
methods, then PHPUnit lifecycle methods (`setUp`, `tearDown`, …), then public methods. When adding a
tearDown to an existing test class, insert it directly before the first `#[Test]`/test method —
never at the end of the class — or run `php-cs-fixer fix` and let it reposition the method.
