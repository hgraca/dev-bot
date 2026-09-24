#!/usr/bin/env python3
"""The PHP op table — single source of truth for the refactor tool's PHP ops.

Subcommands:
    meta              — plugin descriptor JSON for the core's registry
    rules <op>        — JSON array of the Rector rules an op needs, in step order
    render <op> [i]   — read a refactor request as JSON on stdin and write the
                        generated `rector.php` for step `i` (default 0)

Why steps: an op may need more than one rule (a usages rule plus the declaration
rule). Registering both in one config does not compose — the declaration rename
invalidates the reflection the usages rule resolves calls through, so the calls
silently stay put. Each step therefore runs as its own Rector invocation with
exactly one rule, which is also the safety posture everywhere else (`--only`).

Entry shape:
    rule         Rector rule class for the usages half of the op
    vo           value-object class, when that rule is configured with objects
    shape        "vo"  -> withConfiguredRule(Rule, [new VO(<args>)])
                 "map" -> withConfiguredRule(Rule, ['<from>' => '<to>'])
    args         which request fields fill the VO, in order (shape "vo" only)
    qualify      map keys/values are namespace-qualified (the rule matches on
                 the resolved name, so a bare name silently matches nothing)
    declaration  adds a second step registering RenameDeclarationRector for this
                 kind ("function" | "constant" | "class") — Rector's renaming
                 rules are usages-only, so without it the rename is a half-rename
"""

import json
import os
import re
import sys

DECLARATION_RULE = "Devbot\\Refactor\\RenameDeclarationRector"
DECLARATION_REQUIRE = "require_once '/refactor/rules/RenameDeclarationRector.php';"

OPS = {
    "rename-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # RenameMethodRector (not RenameStaticMethodRector) deliberately: it rewrites
    # the declaration as well as the calls, so it needs no second step.
    "rename-static-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    "rename-property": {
        "rule": "Rector\\Renaming\\Rector\\PropertyFetch\\RenamePropertyRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameProperty",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # Annotations live in doc-comments: no separate declaration, so one step.
    "rename-annotation": {
        "rule": "Rector\\Renaming\\Rector\\ClassMethod\\RenameAnnotationRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameAnnotationByType",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # A free function: Rector resolves the call by fully-qualified name, so the
    # namespace is needed — hence `qualify`, and the class field is not.
    "rename-function": {
        "rule": "Rector\\Renaming\\Rector\\FuncCall\\RenameFunctionRector",
        "shape": "map",
        "qualify": True,
        "declaration": "function",
        "requires": ["from", "to"],
    },
    # Constants: the usages rule matches on the BARE name (a qualified key is
    # rejected outright), so no `qualify` here — unlike functions.
    "rename-constant": {
        "rule": "Rector\\Renaming\\Rector\\ConstFetch\\RenameConstantRector",
        "shape": "map",
        "declaration": "constant",
        "requires": ["from", "to"],
    },
    # Cleanup ops: unconfigured rules that act across the scope, changing many
    # things rather than one symbol. No from/to.
    "remove-unused-private-methods": {
        "rule": "Rector\\DeadCode\\Rector\\ClassMethod\\RemoveUnusedPrivateMethodRector",
        "shape": "rules",
        "requires": [],
    },
    "remove-unused-private-properties": {
        "rule": "Rector\\DeadCode\\Rector\\Property\\RemoveUnusedPrivatePropertyRector",
        "shape": "rules",
        "requires": [],
    },
    "privatize-final-class-properties": {
        "rule": "Rector\\Privatization\\Rector\\Property\\PrivatizeFinalClassPropertyRector",
        "shape": "rules",
        "requires": [],
    },
}

LANG = "php"
EXTENSIONS = [".php"]

_NAMESPACE_RE = re.compile(r"^\s*namespace\s+([A-Za-z_][A-Za-z0-9_\\]*)\s*;", re.M)


def php_literal(value: str) -> str:
    """A PHP single-quoted literal. Only backslash and quote need escaping."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def qualify(namespace: str, name: str) -> str:
    return "%s\\%s" % (namespace, name) if namespace else name


def _declaration_re(name: str, kind: str) -> re.Pattern:
    if kind == "function":
        return re.compile(r"^\s*function\s+" + re.escape(name) + r"\s*\(", re.M)
    if kind == "constant":
        return re.compile(r"^\s*const\s+" + re.escape(name) + r"\s*=", re.M)
    return re.compile(r"^\s*(?:final\s+|abstract\s+)*class\s+" + re.escape(name) + r"\b", re.M)


def find_declaring_namespaces(project: str, name: str, kind: str) -> list:
    """Namespaces declaring `name` under the project's source roots ("" = global)."""
    if not project or not os.path.isdir(project):
        return []

    pattern = _declaration_re(name, kind)
    namespaces = []
    for root_name in ("app", "src"):
        root = os.path.join(project, root_name)
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for filename in files:
                if not filename.endswith(".php"):
                    continue
                try:
                    with open(os.path.join(dirpath, filename), encoding="utf-8", errors="replace") as handle:
                        text = handle.read()
                except OSError:
                    continue
                if not pattern.search(text):
                    continue
                match = _NAMESPACE_RE.search(text)
                namespaces.append(match.group(1) if match else "")

    return list(dict.fromkeys(namespaces))  # dedupe, preserving order


def resolve_namespace(request: dict, spec: dict, from_name: str) -> str:
    """The namespace for a qualified op: explicit, else derived, else fatal."""
    explicit = request.get("namespace")
    if explicit:
        return explicit

    kind = spec.get("declaration") or "function"
    candidates = find_declaring_namespaces(request.get("project") or "", from_name, kind)

    if not candidates:
        raise ValueError(
            "could not find a declaration of '%s' under app/ or src/ — "
            "pass --namespace explicitly" % from_name
        )
    if len(candidates) > 1:
        raise ValueError(
            "'%s' is declared in several namespaces (%s) — pass --namespace to pick one"
            % (from_name, ", ".join(ns or "(global)" for ns in candidates))
        )
    return candidates[0]


def steps_for(request: dict, spec: dict):
    """The ordered Rector steps for an op, each self-contained (imports + config)."""
    values = {
        "class": request.get("class") or "",
        "from": request.get("from") or "",
        "to": request.get("to") or "",
    }

    missing = [field for field in spec.get("requires", []) if not values.get(field)]
    if missing:
        raise ValueError(
            "op '%s' requires %s" % (request.get("op"), ", ".join("--" + f for f in missing))
        )

    steps = []

    # Unconfigured rule: runs over the scope and changes whatever it finds, so it
    # takes no from/to and needs no second step.
    if spec["shape"] == "rules":
        return [
            {
                "rule": spec["rule"],
                "imports": ["use %s;" % spec["rule"]],
                "body": ["    ->withRules([%s::class]);" % spec["rule"].rsplit("\\", 1)[-1]],
            }
        ]

    if spec["shape"] == "map":
        namespace = ""
        if spec.get("qualify"):
            namespace = resolve_namespace(request, spec, values["from"])
        key = qualify(namespace, values["from"]) if spec.get("qualify") else values["from"]
        value = qualify(namespace, values["to"]) if spec.get("qualify") else values["to"]
        pair = "        %s => %s," % (php_literal(key), php_literal(value))
    else:
        vo_short = spec["vo"].rsplit("\\", 1)[-1]
        args = ", ".join(php_literal(values[a]) for a in spec["args"])
        pair = "        new %s(%s)," % (vo_short, args)

    short = spec["rule"].rsplit("\\", 1)[-1]
    imports = ["use %s;" % spec["rule"]]
    if spec.get("vo"):
        imports.append("use %s;" % spec["vo"])
    steps.append(
        {
            "rule": spec["rule"],
            "imports": imports,
            "body": [
                "    ->withConfiguredRule(%s::class, [" % short,
                pair,
                "    ]);",
            ],
        }
    )

    if spec.get("declaration"):
        steps.append(
            {
                "rule": DECLARATION_RULE,
                "imports": ["use %s;" % DECLARATION_RULE],
                "require": DECLARATION_REQUIRE,
                "body": [
                    "    ->withConfiguredRule(RenameDeclarationRector::class, [",
                    "        'kind' => %s," % php_literal(spec["declaration"]),
                    "        'from' => %s," % php_literal(values["from"]),
                    "        'to' => %s," % php_literal(values["to"]),
                    "    ]);",
                ],
            }
        )

    return steps


def render(request: dict, index: int = 0) -> int:
    op = request.get("op") or ""
    spec = OPS.get(op)
    if spec is None:
        print("ERROR: unsupported op: %s" % op, file=sys.stderr)
        return 1

    try:
        steps = steps_for(request, spec)
    except ValueError as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 1

    if index < 0 or index >= len(steps):
        print("ERROR: step %d out of range for op %s" % (index, op), file=sys.stderr)
        return 1

    step = steps[index]
    scope = request.get("scope") or ["/app"]

    lines = ["<?php", "", "declare(strict_types=1);", "", "use Rector\\Config\\RectorConfig;"]
    lines += step["imports"]
    if step.get("require"):
        lines += ["", step["require"]]

    lines += [
        "",
        "return RectorConfig::configure()",
        "    ->withPaths([" + ", ".join(php_literal(p) for p in scope) + "])",
    ]
    lines += step["body"]
    lines.append("")

    sys.stdout.write("\n".join(lines))
    return 0


def rules_for(op: str):
    spec = OPS.get(op)
    if spec is None:
        return None
    found = [spec["rule"]]
    if spec.get("declaration"):
        found.append(DECLARATION_RULE)
    return found


def main(argv: list) -> int:
    command = argv[1] if len(argv) > 1 else ""

    if command == "meta":
        print(json.dumps({
            "lang": LANG,
            "extensions": EXTENSIONS,
            "ops": list(OPS),
            "requires": {op: spec.get("requires", []) for op, spec in OPS.items()},
        }))
        return 0

    if command == "rules":
        op = argv[2] if len(argv) > 2 else ""
        found = rules_for(op)
        if found is None:
            print("ERROR: unsupported op: %s" % op, file=sys.stderr)
            return 1
        print(json.dumps(found))
        return 0

    if command == "render":
        index = int(argv[2]) if len(argv) > 2 else 0
        return render(json.load(sys.stdin), index)

    print("ERROR: ops.py: expected one of meta|rules|render", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
