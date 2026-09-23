#!/usr/bin/env python3
"""The PHP op table — single source of truth for the refactor tool's PHP ops.

The plugin (`meta`, and the `--only` value) and the config renderer both read
this module, so **adding an op is one entry in OPS** — not four edits spread
across `plugin.sh` and a renderer.

Subcommands:
    meta            — plugin descriptor JSON for the core's registry
    rule <op>       — the Rector rule class for an op (the `--only` value)
    render          — read a refactor request as JSON on stdin, write the
                      generated `rector.php` to stdout

Entry shape:
    rule   Rector rule class (also the `--only` value)
    vo     value-object class, when the rule is configured with objects
    shape  "vo"  -> withConfiguredRule(Rule, [new VO(<args>)])
           "map" -> withConfiguredRule(Rule, ['<from>' => '<to>'])
    args   which request fields fill the VO, in order (shape "vo" only)
"""

import json
import sys

OPS = {
    "rename-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
    },
    # RenameMethodRector (not RenameStaticMethodRector) deliberately: it rewrites
    # the declaration as well as the calls. The static rule leaves the
    # declaration behind — a half-rename that emits broken code.
    "rename-static-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
    },
    "rename-property": {
        "rule": "Rector\\Renaming\\Rector\\PropertyFetch\\RenamePropertyRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameProperty",
        "shape": "vo",
        "args": ["class", "from", "to"],
    },
}

LANG = "php"
EXTENSIONS = [".php"]


def php_literal(value: str) -> str:
    """A PHP single-quoted literal. Only backslash and quote need escaping."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def render(request: dict) -> int:
    op = request.get("op") or ""
    spec = OPS.get(op)
    if spec is None:
        json.dump({"ok": False, "error": "unsupported op: %s" % op}, sys.stderr)
        return 1

    values = {
        "class": request.get("class") or "",
        "from": request.get("from") or "",
        "to": request.get("to") or "",
    }
    scope = request.get("scope") or ["/app"]

    rule = spec["rule"]
    short = rule.rsplit("\\", 1)[-1]

    lines = [
        "<?php",
        "",
        "declare(strict_types=1);",
        "",
        "use Rector\\Config\\RectorConfig;",
        "use %s;" % rule,
    ]
    if spec.get("vo"):
        lines.append("use %s;" % spec["vo"])
    lines += [
        "",
        "return RectorConfig::configure()",
        "    ->withPaths([" + ", ".join(php_literal(p) for p in scope) + "])",
    ]

    if spec["shape"] == "map":
        config = "        %s => %s," % (php_literal(values["from"]), php_literal(values["to"]))
    else:
        vo_short = spec["vo"].rsplit("\\", 1)[-1]
        args = ", ".join(php_literal(values[a]) for a in spec["args"])
        config = "        new %s(%s)," % (vo_short, args)

    lines += [
        "    ->withConfiguredRule(%s::class, [" % short,
        config,
        "    ]);",
        "",
    ]

    sys.stdout.write("\n".join(lines))
    return 0


def main(argv: list) -> int:
    command = argv[1] if len(argv) > 1 else ""

    if command == "meta":
        print(json.dumps({"lang": LANG, "extensions": EXTENSIONS, "ops": list(OPS)}))
        return 0

    if command == "rule":
        op = argv[2] if len(argv) > 2 else ""
        spec = OPS.get(op)
        if spec is None:
            print("ERROR: unsupported op: %s" % op, file=sys.stderr)
            return 1
        print(spec["rule"])
        return 0

    if command == "render":
        return render(json.load(sys.stdin))

    print("ERROR: ops.py: expected one of meta|rule|render", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
