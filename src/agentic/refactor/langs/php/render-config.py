#!/usr/bin/env python3
"""Render a minimal rector.php carrying exactly ONE rename rule.

Reads a refactor request as JSON on stdin, writes PHP to stdout.

The generated config deliberately registers nothing but the requested rule: the
project's own rector.php may register Laravel/PHPUnit/Carbon/PHP-84 rule sets,
and applying those would rewrite unrelated code. Paths are container paths,
because this config is mounted into the Rector container.
"""

import json
import sys

# op -> (rule class, value-object class)
#
# rename-static-method uses RenameMethodRector for the same reason the plugin
# does: it rewrites the declaration as well as the calls. RenameClassRector is
# deliberately absent — it rewrites references but not the class declaration,
# so a class rename needs declaration (and filename) handling we do not ship yet.
RULES = {
    "rename-method": (
        "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "Rector\\Renaming\\ValueObject\\MethodCallRename",
    ),
    "rename-static-method": (
        "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "Rector\\Renaming\\ValueObject\\MethodCallRename",
    ),
    "rename-property": (
        "Rector\\Renaming\\Rector\\PropertyFetch\\RenamePropertyRector",
        "Rector\\Renaming\\ValueObject\\RenameProperty",
    ),
}


def php_literal(value: str) -> str:
    """A PHP single-quoted literal. Only backslash and quote need escaping."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def main() -> int:
    request = json.load(sys.stdin)

    op = request.get("op") or ""
    klass = request.get("class") or ""
    old = request.get("from") or ""
    new = request.get("to") or ""
    scope = request.get("scope") or ["/app"]

    if op not in RULES:
        json.dump({"ok": False, "error": f"unsupported op: {op}"}, sys.stderr)
        return 1

    rule, value_object = RULES[op]
    short = rule.rsplit("\\", 1)[-1]

    lines = [
        "<?php",
        "",
        "declare(strict_types=1);",
        "",
        "use Rector\\Config\\RectorConfig;",
        f"use {rule};",
    ]
    if value_object:
        lines.append(f"use {value_object};")
    lines += [
        "",
        "return RectorConfig::configure()",
        "    ->withPaths([" + ", ".join(php_literal(p) for p in scope) + "])",
    ]

    if op in ("rename-method", "rename-static-method"):
        config = (
            f"        new MethodCallRename({php_literal(klass)}, "
            f"{php_literal(old)}, {php_literal(new)}),"
        )
    else:  # rename-property
        config = (
            f"        new RenameProperty({php_literal(klass)}, "
            f"{php_literal(old)}, {php_literal(new)}),"
        )

    lines += [
        f"    ->withConfiguredRule({short}::class, [",
        config,
        "    ]);",
        "",
    ]

    sys.stdout.write("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
