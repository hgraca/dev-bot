---
date: 2026-09-09
keywords: ["php", "phparkitect", "HaveCorrespondingUnit", "test-naming"]
trigger-on: ["phparkitect-have-corresponding-unit", "phparkitect-test-naming"]
---

## PHPArkitect test class name must mirror the SUT class name, not just exist

`HaveCorrespondingUnit` maps a test FQCN to a src FQCN by swapping the namespace prefix and stripping the trailing `Test`, then requires that exact class to exist. So a test for `App\Console\Commands\ProjectTrips` must be named `ProjectTripsTest` — naming it `ProjectTripsCommandTest` fails the rule (it maps to `App\Console\Commands\ProjectTripsCommand`, which does not exist) even though the test genuinely covers the class. The violation message is confusing: "should have a matching unit named 'App\Console\Commands\ProjectTripsCommand'". Fix: name the test exactly `{SUT}Test` (drop any extra suffix the SUT doesn't have) and `git mv` the file to match. Check the SUT's actual class name, not the filename pattern of its folder — many `app/Console/Commands` classes are `ProjectTrips`-style without a `Command` suffix. Related but different from the "test with no src class at all" case (see phparkitect-have-corresponding-unit entry, where the fix is folding into an existing test class).
