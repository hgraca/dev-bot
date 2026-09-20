---
date: 2026-08-31
keywords: ["php", "phparkitect", "get-e-dev-tools", "controller-test", "module-decoupling"]
trigger-on: ["phparkitect-controller-folder-naming", "phparkitect-core-port-inheritance", "phparkitect-component-decoupling"]
---

## PHPArkitect (get-e/dev-tools) rules that bite during ports

Three PHPArkitect behaviors from `GetE\DevTools\Php\Arkitect\*` that are non-obvious:

1. **Controller test-correspondence rule uses naive `str_replace('Controller', 'ControllerTest')` over the whole FQCN** — every occurrence is replaced, so a controller's _folder_ must not contain the substring `Controller`. `App\...\Login\LoginController` → test `Tests\...\Login\LoginControllerTest` (fine); `App\...\SamlAuthController\SamlAuthController` → expected test `Tests\...\SamlAuthControllerTest\SamlAuthControllerTest` (impossible — the folder is rewritten too, and the test→SUT rule then maps back to a non-existent class). Rename the folder to avoid the token (`SamlAuth`).

2. **Core components may not implement Port interfaces unless listed in `coreInheritanceExclusions`**: `DependencyRules::create(..., coreInheritanceExclusions: [Voter::class])` — hotels-api's `phparkitect.shared.php` ships a list including `Voter::class`; the single-file config in smaller projects omits it and flags any Core class implementing `App\Core\Port\*`.

3. **`ModulesAreDecoupledFromEachOther` forbids a Core component referencing another component's classes** (no exception list exposed by `DependencyRules::create`). Cross-component entity access must go through a Port: the Port (`App\Core\Port\X\`) may reference the other component's domain classes (e.g. return `App\Core\Component\User\Domain\User`), and the consuming component calls the port without naming the entity in code (phpdoc-only `@param`/`@return` — PHPArkitect scans code references, not phpdoc; PHPStan still resolves via the port's signature). Presentation may not depend on Infrastructure either (layer rule), so the service must stay in Core behind the port.
