#!/usr/bin/env python3
"""Render one Kafka connection into the config mcp-confluent consumes.

Usage:
  render_config.py <connection-name>                      < catalogue.json
  render_config.py --resolve <dotenv> <connection-name>    < catalogue.json
  render_config.py --redact <connection-name>              < catalogue.json

The catalogue (`kafka_connections` in .devbot.global.jsonc) arrives on STDIN so
a literal value never has to pass through argv, which is world-readable.

    connections:
      <name>:
        type: direct
        read_only: true
        kafka:
          bootstrap_servers: "host:9092"
          auth: {type: api_key, key: "${...}", secret: "${...}"}
          extra_properties: {sasl.mechanisms: "SCRAM-SHA-512"}
        schema_registry:              # omitted when the connection has none
          endpoint: "https://sr.local"
          auth: {...}

A `${VAR}` reference is resolved here — from the process environment, then the
repo `.env` — and the value is written into the document, so a credential is
named exactly once, in the catalogue, and reaches the server through the 0600
config file. Without `--resolve` the references stay verbatim, which is what
`--print-config` shows.

Credentials go in the server's NAMED `auth` block, never in `extra_properties`:
1.6.1's schema rejects `sasl.username`, `sasl.password` and `bootstrap.servers`
there. `extra_properties` is the override path for librdkafka settings such as
`sasl.mechanisms` (SCRAM) or a `security.protocol` that differs from the
`SASL_SSL` a named `auth` block implies.

Every emitted scalar is a JSON string, which is also a valid YAML double-quoted
scalar: a broker string containing `:` or `#` cannot change the document's shape.

Exit codes: 0 ok, 2 configuration error (message on stderr), 3 usage error.
"""

import json
import os
import re
import sys

# ${VAR} and ${VAR:-default} — and `$${...}`, the server's own literal escape.
INTERPOLATION = re.compile(r"(?<!\$)\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")
QUOTES = chr(34) + chr(39)

TOP_KEYS = {"bootstrap_servers", "auth", "extra_properties", "schema_registry"}
SR_KEYS = {"endpoint", "auth"}
AUTH_KEYS = {"type", "key", "secret"}
# Plain scalars need no quotes in YAML; everything else is emitted as a JSON
# string, which is a valid double-quoted YAML scalar.
PLAIN_KEY = re.compile(r"^[A-Za-z0-9_.-]+$")
SINGLE_REFERENCE = re.compile(r"^\$\{[A-Za-z_][A-Za-z0-9_]*(?::-([^}]*))?\}$")
RESERVED_ENV = {
    "PATH",
    "HOME",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "DO_NOT_TRACK",
    "NODE_OPTIONS",
    "LD_PRELOAD",
}


def fail(message):
    print("kafka: %s" % message, file=sys.stderr)
    sys.exit(2)


def scalar(value):
    return json.dumps(value, ensure_ascii=False)


def key(name):
    return name if PLAIN_KEY.match(name) else scalar(name)


def require_string_map(value, where):
    """A flat map of string to string — an int would silently become a number."""
    if not isinstance(value, dict):
        fail("%s must be an object of string values" % where)
    for name, item in value.items():
        if not isinstance(item, str):
            fail("%s.%s must be a string, not %s" % (where, name, type(item).__name__))


def require_non_empty_string(value, where):
    if not isinstance(value, str) or not value.strip():
        fail("%s must be a non-empty string" % where)


def require_auth(value, where):
    """The server's named credential block — the only place a secret is accepted."""
    if not isinstance(value, dict):
        fail("%s must be an object with type, key and secret" % where)
    unknown = sorted(set(value) - AUTH_KEYS)
    if unknown:
        fail(
            "%s has unknown key(s) %s — expected %s"
            % (where, ", ".join(unknown), ", ".join(sorted(AUTH_KEYS)))
        )
    # api_key is the only type a direct connection documents; anything else
    # would be rendered and then rejected at launch, far from the config error.
    if value.get("type") != "api_key":
        fail('%s.type must be "api_key"' % where)
    for field in ("key", "secret"):
        require_non_empty_string(value.get(field), "%s.%s" % (where, field))


def require_endpoint(value, where):
    require_non_empty_string(value, where)
    if not value.startswith(("http://", "https://")):
        fail("%s must be an http:// or https:// URL" % where)


def load_dotenv(path):
    """NAME -> value, as written in the file. Nothing in it is executed.

    Lossless where it matters: only a MATCHING pair of surrounding quotes is
    syntax, and whatever follows the first `=` is the value — including spaces,
    further `=` characters and interior quotes.
    """
    values = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.rstrip("\n").rstrip("\r")
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export ") :]
                if "=" not in line:
                    continue
                key, _, value = line.partition("=")
                if len(value) >= 2 and value[0] == value[-1] and value[0] in QUOTES:
                    value = value[1:-1]
                values[key.strip()] = value
    except OSError:
        pass
    return values


def resolve(name, dotenv, default=None):
    """(found, value) — the server's own semantics: absent falls to the default,
    and a variable present but EMPTY is a value, not a missing one."""
    if name in os.environ:
        return True, os.environ[name]
    if name in dotenv:
        return True, dotenv[name]
    if default is not None:
        return True, default
    return False, None


def present(container, name):
    """The value when the key is present, else {} — so a falsy wrong type fails.

    `conn.get(name) or {}` would turn a typo like `"env": []` into an empty map
    and render a connection that silently ignores what the user wrote.
    """
    return container[name] if name in container else {}


def resolve_value(value, dotenv, missing):
    """Replace `${VAR}` in one string, recording the names nothing supplies."""
    if not isinstance(value, str):
        return value

    def replace(match):
        ref, default = match.group(1), match.group(2)
        found, resolved = resolve(ref, dotenv, default)
        if not found:
            if ref not in missing:
                missing.append(ref)
            return match.group(0)
        return resolved

    return INTERPOLATION.sub(replace, value)


def resolve_connection(conn, dotenv, missing):
    """A copy of the connection with every reference resolved as data."""
    resolved = dict(conn)
    resolved["bootstrap_servers"] = resolve_value(
        resolved.get("bootstrap_servers"), dotenv, missing
    )
    auth = resolved.get("auth")
    if isinstance(auth, dict):
        resolved["auth"] = {
            key: resolve_value(value, dotenv, missing) for key, value in auth.items()
        }
    extra = resolved.get("extra_properties")
    if isinstance(extra, dict):
        resolved["extra_properties"] = {
            key: resolve_value(value, dotenv, missing) for key, value in extra.items()
        }
    registry = resolved.get("schema_registry")
    if isinstance(registry, dict):
        registry = dict(registry)
        registry["endpoint"] = resolve_value(registry.get("endpoint"), dotenv, missing)
        if isinstance(registry.get("auth"), dict):
            registry["auth"] = {
                key: resolve_value(value, dotenv, missing)
                for key, value in registry["auth"].items()
            }
        resolved["schema_registry"] = registry
    return resolved


REDACTED = "***"
# `extra_properties` is librdkafka's, and it is where a password ends up when a
# connection needs SCRAM or a TLS key passphrase. A property the server treats as
# a credential is masked in inspection output like `auth` is; a reference stays
# visible, since the name is what a reader needs.
SENSITIVE_PROPERTY = re.compile(r"password|secret|token|sasl\.username|ssl\.key", re.I)


def redact_if_literal(value):
    """Keep a ${VAR} reference visible; mask anything else.

    `--print-config` exists to show a connection's SHAPE. A reference names the
    variable it needs — useful — while a literal is a secret that would otherwise
    land in a terminal, a log or a pasted issue.
    """
    if not isinstance(value, str):
        return value
    return REDACTED if not SINGLE_REFERENCE.match(value) else value


def render(name, conn, redact=False):
    """The YAML document for one connection, as a list of lines."""
    if not isinstance(conn, dict):
        fail("'%s' must be an object, not %s" % (name, type(conn).__name__))

    unknown = sorted(set(conn) - TOP_KEYS)
    if unknown:
        fail(
            "'%s' has unknown key(s) %s — expected %s"
            % (name, ", ".join(unknown), ", ".join(sorted(TOP_KEYS)))
        )

    require_non_empty_string(conn.get("bootstrap_servers"), "%s.bootstrap_servers" % name)
    extra = present(conn, "extra_properties")
    require_string_map(extra, "%s.extra_properties" % name)

    auth = conn.get("auth")
    if auth is not None:
        require_auth(auth, "%s.auth" % name)

    registry = conn.get("schema_registry")
    if registry is not None:
        if not isinstance(registry, dict):
            fail("%s.schema_registry must be an object" % name)
        unknown = sorted(set(registry) - SR_KEYS)
        if unknown:
            fail(
                "%s.schema_registry has unknown key(s) %s — expected %s"
                % (name, ", ".join(unknown), ", ".join(sorted(SR_KEYS)))
            )
        require_endpoint(registry.get("endpoint"), "%s.schema_registry.endpoint" % name)
        if registry.get("auth") is not None:
            require_auth(registry["auth"], "%s.schema_registry.auth" % name)

    if redact:
        # Mask the locals the lines are built from, not a copy of the connection.
        if auth is not None:
            auth = {
                **auth,
                **{f: redact_if_literal(auth[f]) for f in ("key", "secret") if f in auth},
            }
        if extra:
            extra = {
                prop: (redact_if_literal(value) if SENSITIVE_PROPERTY.search(prop) else value)
                for prop, value in extra.items()
            }
        if registry is not None and isinstance(registry.get("auth"), dict):
            sr_auth = {
                **registry["auth"],
                **{
                    f: redact_if_literal(registry["auth"][f])
                    for f in ("key", "secret")
                    if f in registry["auth"]
                },
            }
            registry = {**registry, "auth": sr_auth}

    lines = ["connections:", "  %s:" % key(name), "    type: direct"]
    # Belt and braces on top of the allowlist: a mutating tool that an upgrade
    # adds without the allowlist naming it still cannot run on this connection.
    lines.append("    read_only: true")
    lines.append("    kafka:")
    lines.append("      bootstrap_servers: %s" % scalar(conn["bootstrap_servers"]))
    if auth is not None:
        lines.extend(auth_lines(auth, "      "))
    if extra:
        lines.append("      extra_properties:")
        for prop, value in extra.items():
            lines.append("        %s: %s" % (key(prop), scalar(value)))

    if registry is not None:
        lines.append("    schema_registry:")
        lines.append("      endpoint: %s" % scalar(registry["endpoint"]))
        if registry.get("auth") is not None:
            lines.extend(auth_lines(registry["auth"], "      "))

    return lines


def auth_lines(auth, indent):
    return [
        "%sauth:" % indent,
        "%s  type: %s" % (indent, scalar(auth["type"])),
        "%s  key: %s" % (indent, scalar(auth["key"])),
        "%s  secret: %s" % (indent, scalar(auth["secret"])),
    ]


def main(argv):
    # --resolve <dotenv> <connection-name>: write the document the server reads,
    # with every reference resolved. Without it the references stay verbatim,
    # which is what --print-config shows.
    resolve_mode = len(argv) == 4 and argv[1] == "--resolve"
    redact = argv[1] == "--redact" if len(argv) > 1 else False
    if redact:
        argv = [argv[0]] + argv[2:]
    if not resolve_mode and len(argv) != 2:
        print(
            "usage: render_config.py [--resolve <dotenv> | --redact] <connection-name>",
            file=sys.stderr,
        )
        return 3

    if resolve_mode:
        name = argv[3]
    else:
        name = argv[1]
    try:
        catalogue = json.load(sys.stdin)
    except ValueError as exc:
        fail("the kafka_connections catalogue is not valid JSON (%s)" % exc)

    if not isinstance(catalogue, dict):
        fail("kafka_connections must be an object of named connections")
    if name not in catalogue:
        # Nothing renders for a name the machine never declared, and init must
        # not publish a manifest whose server cannot start.
        fail("connection '%s' is not declared in kafka_connections" % name)

    missing = []
    connection = catalogue[name]
    if resolve_mode:
        connection = resolve_connection(connection, load_dotenv(argv[2]), missing)

    lines = render(name, connection, redact=redact)
    lines.append("")
    sys.stdout.write("\n".join(lines))
    for ref in missing:
        print(ref, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
