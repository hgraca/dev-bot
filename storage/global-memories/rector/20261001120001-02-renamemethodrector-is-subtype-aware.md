---
date: 2026-10-01
keywords: ["rector", "RenameMethodRector", "interface", "subtype", "rename"]
trigger-on: ["rector-rename-method", "rector-interface-rename"]
---

## RenameMethodRector is subtype-aware — an interface rename reaches its implementors

`Rector\Renaming\Rector\MethodCall\RenameMethodRector` does not match only the class
named in its `MethodCallRename` value object. Its declaration pass runs on `Class_`,
`Interface_` and `Trait_` nodes and accepts a method whose class reflection `is()` the
configured class — any subtype or implementor (`NodeTypeResolver::isMethodStaticCallOrClassMethodObjectType`,
whose class branch calls `$classReflection->is($objectType->getClassName())`). Renaming
a method on an interface therefore rewrites the implementing method in every subclass
and test double, **provided those files are inside `withPaths()`**. This is why the
rename op needs no separate declaration rule for methods (unlike functions, constants
and classes, which need the custom `RenameDeclarationRector`), and why a scope that
excludes `tests/` yields a broken implementor rather than a merely stale reference.
