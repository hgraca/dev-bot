#!/usr/bin/env python3
"""
create-use-case-map — auto-generate use-case-map JSON from PHP codebase.

Scans a PHP project using get-e/message-bus to trace call chains:
  Entry Point → Command → Handler → Port → Adapter → HTTP Client

Uses graphify knowledge graph for structural discovery (communities, file paths).
Reads PHP class declarations for authoritative type information (implements, extends).
Reads PHP dispatch/call statements for call-chain tracing.

Outputs a schema-compliant JSON file at the specified path.

Usage:
  ./create-use-case-map.py [--project-root DIR] [--output FILE] [--component NAME]

Requirements:
  - graphify-out/graph.json at project root (from graphify extract)
  - PHP project with get-e/message-bus library conventions
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict, OrderedDict
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class Unit:
    title: str = ""
    info: str = ""
    color: str = ""
    indentation: int = 0
    items: list = field(default_factory=list)

    # UseCase-specific (not serialized if absent)
    command: Optional["Unit"] = None
    handler: Optional["Unit"] = None
    dispatchMode: str = ""


@dataclass
class Column:
    title: str = ""
    color: str = ""
    items: list = field(default_factory=list)


@dataclass
class SubSection:
    title: str = ""
    items: list = field(default_factory=list)


@dataclass
class Section:
    title: str = ""
    items: list = field(default_factory=list)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def rx(pattern, text):
    m = re.search(pattern, text)
    return m.group(1) if m else ""


def rx_all(pattern, text):
    return re.findall(pattern, text)


PHP_DECL_PATTERN = re.compile(
    r"(?P<type>class|interface|trait|enum)"
    r"(?:\s+(?:abstract|final|readonly)){0,3}"  # handles modifiers
    r"\s+(?P<name>\w+)"
    r"(?:\s+extends\s+(?P<extends>[A-Za-z_]\w*(?:\\\\[A-Za-z_]\w*)*))?"
    r"(?:\s+implements\s+(?P<implements>[A-Za-z_]\w*(?:,\s*[A-Za-z_]\w*)*))?"
)


def read_php_declaration(filepath):
    """Read the class/interface declaration from a PHP file.

    Reads the entire file looking for the class/interface/trait declaration line,
    which is the authoritative source for type relationships (implements, extends).

    Returns dict with keys: type, name, extends, implements (list)
    or None if no declaration found.
    """
    try:
        with open(filepath, "r", errors="ignore") as f:
            content = f.read(15000)  # enough for most files
    except (IOError, OSError):
        return None

    m = PHP_DECL_PATTERN.search(content)
    if not m:
        return None

    result = {
        "type": m.group("type"),
        "name": m.group("name"),
        "extends": "",
        "implements": [],
    }
    if m.group("extends"):
        result["extends"] = m.group("extends").strip()
    if m.group("implements"):
        # Split on commas, strip whitespace and backslash prefixes
        result["implements"] = [
            i.strip().lstrip("\\") for i in m.group("implements").split(",")
        ]
    return result


def graphify_node_label(filepath, root_dir):
    """Convert a PHP filepath to a likely graphify node label.

    graphify strips the leading app/ or src/ prefix and file extension.
    """
    rel = os.path.relpath(filepath, root_dir)
    # Remove app/ or src/ prefix
    for prefix in ["app/", "src/"]:
        if rel.startswith(prefix):
            rel = rel[len(prefix) :]
            break
    # Remove .php extension
    if rel.endswith(".php"):
        rel = rel[:-4]
    # Replace directory separators
    return rel.replace("/", "_").replace("\\", "_")


# ---------------------------------------------------------------------------
# Graph-based scanner
# ---------------------------------------------------------------------------


class GraphScanner:
    """Scans a PHP codebase using ast-grep + PHP reflection + PHP declarations."""

    MESSAGE_BUS_INTERFACES = {
        "Command": "command",
        "CommandHandler": "handler",
        "Event": "event",
        "EventHandler": "listener",
        "EventListener": "listener",
        "Query": "query",
        "QueryHandler": "query_handler",
    }

    def __init__(
        self,
        project_root,
        component=None,
        arch_config_path=None,
        http_client_types_path=None,
        dispatch_patterns_path=None,
    ):
        self.root = project_root
        self.component = component

        # Load configs from conf/php/ (relative to src/)
        self._arch_config = self._load_config(
            arch_config_path or "../conf/php/structure-explicit-architecture.php"
        )
        self._http_client_types = self._load_config(
            http_client_types_path or "../conf/php/http-clients-types.php", default=[]
        )
        self._dispatch_patterns = self._load_config(
            dispatch_patterns_path
            or "../conf/php/get-e-message-bus-dispatch-patterns.php",
            default=[],
        )
        self._port_methods = set()

        # Graph data
        self._graph = None
        self._nodes_by_label = {}  # label → node
        self._nodes_by_file = {}  # source_file → node
        self._communities = {}  # community_id → [nodes]

        # Discovered code units
        self._commands = {}  # fqcn → filepath
        self._handlers = {}  # fqcn → filepath
        self._events = {}  # fqcn → filepath
        self._listeners = {}  # fqcn → filepath
        self._queries = {}  # fqcn → filepath
        self._query_handlers = {}  # fqcn → filepath
        self._callback_handlers = {}  # fqcn → filepath (classes implementing CallbackHandler)
        self._ports = {}  # name → {fqcn, filepath, methods}
        self._adapters = {}  # fqcn → filepath
        self._http_clients = {}  # fqcn → filepath
        self._entry_points = []  # (fqcn, filepath, kind, is_scheduled)
        self._listener_entries = {}  # fqcn → {event_fqcn, method} for listener entry points
        self._all_php_files = []

    def _load_config(self, path, default=None):
        """Load a PHP config file by parsing the PHP array structure.

        If path is relative, looks in the scripts directory next to this file.
        If absolute, uses it as-is.
        """
        if os.path.isabs(path):
            config_path = path
        else:
            config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), path)
        if not os.path.isfile(config_path):
            if default is not None:
                return default
            print(f"  WARNING: config not found: {config_path}", file=sys.stderr)
            return {}
        try:
            with open(config_path) as f:
                php_code = f.read()
            # Extract the return statement content between return [ and the last ];
            m = re.search(r"return\s*(\[.*?\])\s*;", php_code, re.DOTALL)
            if not m:
                return default if default is not None else {}
            return self._parse_php_array(m.group(1))
        except Exception as e:
            if default is not None:
                return default
            return {}

    def _parse_php_array(self, php_str):
        """Parse a PHP array literal into a Python dict/list."""
        php_str = re.sub(r"//.*", "", php_str)
        php_str = re.sub(r"/\*.*?\*/", "", php_str, flags=re.DOTALL)

        def convert_value(v):
            v = v.strip()
            if v.startswith("'") or v.startswith('"'):
                return v.strip("'\"").replace("\\\\", "\\")
            if v == "true":
                return True
            if v == "false":
                return False
            if v == "null":
                return None
            try:
                return int(v)
            except ValueError:
                pass
            try:
                return float(v)
            except ValueError:
                pass
            return v.strip("'\"")

        # Parse [key => value, ...] or [value, ...]
        # Simple recursive parser for flat structures
        result = {}
        is_list = True

        # Remove outer brackets
        inner = php_str.strip()
        if inner.startswith("["):
            inner = inner[1:]
        if inner.endswith("]"):
            inner = inner[:-1]
        if not inner.strip():
            return [] if is_list else {}

        # Split by top-level commas
        items = self._split_php_items(inner)

        for item in items:
            item = item.strip()
            if not item:
                continue
            if "=>" in item:
                is_list = False
                key, val = item.split("=>", 1)
                key = convert_value(key.strip())
                # Check if value is a sub-array
                if val.strip().startswith("["):
                    val = self._parse_php_array(val.strip())
                elif val.strip().startswith("'"):
                    val = val.strip().strip("'")
                elif val.strip().startswith('"'):
                    val = val.strip().strip('"')
                else:
                    val = convert_value(val.strip())
                result[key] = val
            else:
                val = item.strip()
                if val.startswith("["):
                    result[len(result)] = self._parse_php_array(val)
                else:
                    result[len(result)] = convert_value(val)

        if is_list:
            return [result[k] for k in sorted(result.keys())]
        return result

    def _split_php_items(self, s):
        """Split a PHP array content by top-level commas."""
        items = []
        depth_bracket = 0
        depth_paren = 0
        current = []
        in_string = None
        i = 0
        while i < len(s):
            ch = s[i]
            if in_string:
                if ch == "\\" and i + 1 < len(s):
                    current.append(ch)
                    current.append(s[i + 1])
                    i += 2
                    continue
                if ch == in_string:
                    in_string = None
                current.append(ch)
            elif ch in ("'", '"'):
                in_string = ch
                current.append(ch)
            elif ch == "[":
                depth_bracket += 1
                current.append(ch)
            elif ch == "]":
                depth_bracket -= 1
                current.append(ch)
            elif ch == "(":
                depth_paren += 1
                current.append(ch)
            elif ch == ")":
                depth_paren -= 1
                current.append(ch)
            elif ch == "," and depth_bracket == 0 and depth_paren == 0:
                items.append("".join(current))
                current = []
            else:
                current.append(ch)
            i += 1
        if current:
            items.append("".join(current))
        return items

    def scan(self):
        """Main scan — discovers code units via filesystem + PHP reflection + ast-grep."""
        self._load_graph()
        self._index_php_files()
        self._discover_code_units()
        return self

    def _load_graph(self):
        """No-op — graph loading removed. Filesystem walk used instead."""
        pass

    def _index_php_files(self):
        """Build a list of all PHP file paths by walking the filesystem.

        Scans all configured directories (src, entry points, ports, adapters)
        to find PHP files for analysis.
        """
        seen = set()

        # Walk all configured directories
        scan_dirs = set()
        # Main src dirs
        for d in ["app", "src"]:
            dpath = os.path.join(self.root, d)
            if os.path.isdir(dpath):
                scan_dirs.add(dpath)
        # Entry point dirs from config
        ep_config = self._arch_config.get("entry_points", {})
        for kind, dirs in ep_config.items():
            for d in dirs:
                dpath = os.path.join(self.root, d)
                if os.path.isdir(dpath):
                    scan_dirs.add(dpath)
        # Adapter dirs from config
        adapter_dirs = self._arch_config.get("adapters", {}).get("directories", [])
        for d in adapter_dirs:
            dpath = os.path.join(self.root, d)
            if os.path.isdir(dpath):
                scan_dirs.add(dpath)
        # Port dirs from config
        port_dirs = self._arch_config.get("ports", {}).get("directories", [])
        for d in port_dirs:
            dpath = os.path.join(self.root, d)
            if os.path.isdir(dpath):
                scan_dirs.add(dpath)

        for dpath in scan_dirs:
            for dirpath, dirnames, filenames in os.walk(dpath):
                # Skip vendor, test, cache dirs
                dirnames[:] = [
                    d
                    for d in dirnames
                    if d
                    not in ("vendor", "tests", "Test", "node_modules", "cache", ".git")
                ]
                for fn in filenames:
                    if not fn.endswith(".php"):
                        continue
                    full = os.path.join(dirpath, fn)
                    if full not in seen:
                        seen.add(full)
                        rel = os.path.relpath(full, self.root)
                        self._all_php_files.append(rel)

    def _matches_component(self, filepath):
        """Check if a filepath matches the component filter."""
        if not self.component:
            return True
        return (
            f"/Component/{self.component}/" in filepath
            or f"/{self.component}/" in filepath
            or self.component.lower() in filepath.lower()
        )

    def _discover_code_units(self):
        """Discover all code units using PHP reflection (handles inheritance chains).

        Uses dockerized PHP to reflect on classes and get ALL implemented
        interfaces (including inherited via extends chains).
        """
        php_cmd = self._find_php_command()
        if not php_cmd:
            print(
                "  WARNING: PHP CLI not found — falling back to declaration parsing",
                file=sys.stderr,
            )
            self._discover_code_units_fallback()
            return

        # Feed all PHP files to the reflection script
        # Script path relative to project root (for Docker: /app/...)
        # The project root is mounted at /app, so conf/php/ is accessible.
        if "docker" in php_cmd[0]:
            reflect_script = "/app/conf/php/get-e-message-bus-types.php"
            php_root = "/app"
        else:
            reflect_script = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                "../conf/php/get-e-message-bus-types.php",
            )
            php_root = self.root

        php_files = [f for f in self._all_php_files if f.endswith(".php")]
        if not php_files:
            return

        # Write file list to a temp file inside the project (accessible via Docker mount)
        tmp_list = os.path.join(self.root, ".php_reflect_tmp.txt")
        try:
            with open(tmp_list, "w") as f:
                f.write("\n".join(php_files))
            with open(tmp_list) as fh:
                try:
                    proc = subprocess.run(
                        php_cmd + [reflect_script, php_root],
                        stdin=fh,
                        capture_output=True,
                        text=True,
                        timeout=180,
                    )
                except FileNotFoundError:
                    print("  WARNING: PHP command not found", file=sys.stderr)
                    return
        finally:
            if os.path.isfile(tmp_list):
                os.unlink(tmp_list)

        if proc.returncode != 0:
            print(
                f"  WARNING: PHP reflection returned {proc.returncode}", file=sys.stderr
            )
            if proc.stderr:
                print(f"    stderr: {proc.stderr[:200]}", file=sys.stderr)
            return

        try:
            data = json.loads(proc.stdout)
        except json.JSONDecodeError:
            print("  WARNING: PHP reflection output not valid JSON", file=sys.stderr)
            return

        # Check for error from PHP script
        if "error" in data:
            print(f"  PHP ERROR: {data['error']}", file=sys.stderr)
            return

        use_cases = data.get("use-cases", {})
        php_queries = data.get("queries", {})
        mb_events = data.get("events", {})

        # Build command/handler/event/listener maps from PHP output
        for cmd_fqcn, handler_fqcn in use_cases.items():
            cmd_file = self._fqcn_to_filepath(cmd_fqcn)
            handler_file = self._fqcn_to_filepath(handler_fqcn)
            if cmd_file:
                self._commands[cmd_fqcn] = cmd_file
            if handler_file:
                self._handlers[handler_fqcn] = handler_file

        # Build query/query-handler maps (always sync, different colors)
        for q_fqcn, qh_fqcn in php_queries.items():
            q_file = self._fqcn_to_filepath(q_fqcn)
            qh_file = self._fqcn_to_filepath(qh_fqcn)
            if q_file:
                self._queries[q_fqcn] = q_file
            if qh_file:
                self._query_handlers[qh_fqcn] = qh_file

        for event_fqcn, listener_list in mb_events.items():
            event_file = self._fqcn_to_filepath(event_fqcn)
            if event_file:
                self._events[event_fqcn] = event_file
            for listener_entry in listener_list:
                listener_fqcn = listener_entry.split("::")[0]
                method_name = (
                    listener_entry.split("::")[1]
                    if "::" in listener_entry
                    else "handle"
                )
                listener_file = self._fqcn_to_filepath(listener_fqcn)
                if listener_file:
                    self._listeners[listener_fqcn] = listener_file
                    # Add listener as an entry point
                    self._entry_points.append(
                        (listener_fqcn, listener_file, "listnr", False)
                    )
                    self._listener_entries[listener_fqcn] = {
                        "event_fqcn": event_fqcn,
                        "method": method_name,
                    }

        # Discover non-message-bus units (ports, adapters, entry points, etc.)
        self._discover_non_message_bus_units()

        print(
            f"  Message-bus discovery: {len(self._commands)} commands, "
            f"{len(self._handlers)} handlers, {len(self._queries)} queries, "
            f"{len(self._events)} events, {len(self._listeners)} listeners",
            file=sys.stderr,
        )

        print(
            f"  Discovery: {len(self._commands)} commands, {len(self._handlers)} handlers",
            file=sys.stderr,
        )
        print(
            f"  {len(self._ports)} ports, {len(self._adapters)} adapters, {len(self._http_clients)} clients",
            file=sys.stderr,
        )
        print(f"  {len(self._entry_points)} entry points", file=sys.stderr)

    def _fqcn_to_filepath(self, fqcn):
        """Convert a PHP FQCN to a file path relative to the project root.

        Uses PSR-4 convention (App prefix to app/) and falls back to file search.
        """
        short_name = fqcn.split("\\")[-1]
        # PSR-4 convention
        rel = fqcn.replace("\\", "/") + ".php"
        if rel.startswith("App/"):
            rel = "app/" + rel[4:]
        full = os.path.join(self.root, rel)
        if os.path.isfile(full):
            return rel

        # Search all PHP files for the class name
        for fpath in self._all_php_files:
            if fpath.endswith("/" + short_name + ".php"):
                return fpath

        return ""

    def _discover_non_message_bus_units(self):
        """Discover ports, adapters, entry points, HTTP clients.

        These aren't message-bus types and need file-level declaration reading.
        """
        for rel_path in self._all_php_files:
            if not rel_path.endswith(".php"):
                continue
            full_path = os.path.join(self.root, rel_path)
            decl = read_php_declaration(full_path)
            if not decl:
                continue
            ns = self._extract_namespace(full_path)
            fqcn = ns + "\\" + decl["name"] if ns else decl["name"]
            extends = decl["extends"]
            cls_type = decl["type"]

            # Ports: interfaces in configured port directories
            port_dirs = self._arch_config.get("ports", {}).get(
                "directories", ["app/Core/Port/"]
            )
            if (
                any(rel_path.startswith(d) for d in port_dirs)
                and cls_type == "interface"
            ):
                methods = self._extract_methods(full_path)
                self._ports[decl["name"]] = {
                    "fqcn": fqcn,
                    "file": rel_path,
                    "methods": methods,
                }
                self._port_methods.update(methods)
                continue

            # CLI commands: extend a Command base class
            cli_dirs = self._arch_config.get("entry_points", {}).get(
                "cli", ["app/Presentation/Cli/"]
            )
            if (
                extends
                and "Command" in extends
                and any(rel_path.startswith(d) for d in cli_dirs)
            ):
                is_scheduled = False
                try:
                    with open(full_path, "r", errors="ignore") as f:
                        content = f.read(3000)
                    if re.search(
                        r"schedule|isDue|cron|every\w+\(", content, re.IGNORECASE
                    ):
                        is_scheduled = True
                except (IOError, OSError):
                    pass
                self._entry_points.append((fqcn, rel_path, "cli", is_scheduled))

            # HTTP Controllers
            http_dirs = self._arch_config.get("entry_points", {}).get("http", [])
            if rel_path.endswith("Controller.php") and any(
                rel_path.startswith(d) for d in http_dirs
            ):
                self._entry_points.append((fqcn, rel_path, "ctrl", False))

            # Adapters: classes in configured adapter directories implementing an interface
            adapter_dirs = self._arch_config.get("adapters", {}).get(
                "directories", ["app/Infrastructure/"]
            )
            if any(rel_path.startswith(d) for d in adapter_dirs) and decl["implements"]:
                self._adapters[fqcn] = rel_path

            # HTTP Clients: extend or use known HTTP client base types
            http_base_types = self._http_client_types
            is_http_client = False
            if extends:
                for base in http_base_types:
                    short = base.split("\\")[-1]
                    if extends == short or extends == base:
                        is_http_client = True
                        break
            if not is_http_client and decl["implements"]:
                for iface in decl["implements"]:
                    for base in http_base_types:
                        short = base.split("\\")[-1]
                        if iface == short or iface == base:
                            is_http_client = True
                            break
            if is_http_client:
                self._http_clients[fqcn] = rel_path

            # Callback handlers: classes implementing configured callback interface
            cb_interface = self._arch_config.get("callbacks", {}).get("interface", "")
            if cb_interface and decl["implements"]:
                short = cb_interface.split("\\")[-1]
                if short in decl["implements"]:
                    self._callback_handlers[fqcn] = rel_path

    def _find_php_command(self):
        """Find the PHP CLI command — try local first, then Docker-based.

        Detects PHP version from composer.json and uses the matching Docker image.
        """
        # Detect project language and PHP version from composer.json
        composer_path = os.path.join(self.root, "composer.json")
        php_version = None
        if os.path.isfile(composer_path):
            try:
                with open(composer_path) as f:
                    composer = json.load(f)
                php_require = (
                    composer.get("require", {}).get("php")
                    or composer.get("require-dev", {}).get("php")
                    or ""
                )
                if php_require:
                    # Extract major.minor from constraint strings like:
                    # "^8.4", ">=8.1", "~8.3.0", "8.2.*", ">=7.4", "^8.1.0"
                    m = re.search(r"(\d+)\.(\d+)", php_require)
                    if m:
                        php_version = f"{m.group(1)}.{m.group(2)}"
            except (json.JSONDecodeError, IOError, OSError):
                pass
        else:
            print(
                "  ERROR: No composer.json found — only PHP projects are supported.\n"
                "  To add support for another language, create a language adapter\n"
                "  following the pattern in conf/php/get-e-message-bus-types.php",
                file=sys.stderr,
            )
            return None

        # Try local PHP
        try:
            result = subprocess.run(
                ["php", "--version"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                return ["php"]
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        # Try Docker-based PHP matching the project's composer.json version
        php_image = f"php:{php_version or '8.4'}-cli"
        # Handle symlinks: .opencode/skills/telamon may point outside the project
        skills_dir = os.path.join(self.root, ".opencode", "skills", "telamon")
        extra_mount = []
        if os.path.islink(skills_dir):
            target = os.readlink(skills_dir)
            if not os.path.isabs(target):
                target = os.path.join(os.path.dirname(skills_dir), target)
            if os.path.isdir(target):
                extra_mount = ["-v", f"{target}:/app/.opencode/skills/telamon"]
        try:
            docker_cmd = (
                [
                    "docker",
                    "run",
                    "--rm",
                    "-i",  # needed for stdin passthrough to PHP script
                    "-v",
                    f"{self.root}:/app",
                ]
                + extra_mount
                + [
                    "-w",
                    "/app",
                    php_image,
                    "php",
                ]
            )
            result = subprocess.run(
                docker_cmd + ["--version"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                return docker_cmd
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        return None

    def _discover_code_units_fallback(self):
        """Fallback: read PHP declaration lines directly (no inheritance chain support)."""
        interface_short_names = set(self.MESSAGE_BUS_INTERFACES.keys())

        for rel_path in self._all_php_files:
            if not rel_path.endswith(".php"):
                continue
            full_path = os.path.join(self.root, rel_path)
            decl = read_php_declaration(full_path)
            if not decl:
                continue
            name = decl["name"]
            ns = self._extract_namespace(full_path)
            fqcn = ns + "\\" + name if ns else name
            implemented = set(decl["implements"])
            matched_interfaces = implemented & interface_short_names

            if not matched_interfaces:
                if name.endswith("Handler") and "/UseCase/" in rel_path:
                    self._handlers[fqcn] = rel_path
                    continue
                if decl["type"] == "interface" and "/Port/" in rel_path:
                    methods = self._extract_methods(full_path)
                    self._ports[name] = {
                        "fqcn": fqcn,
                        "file": rel_path,
                        "methods": methods,
                    }
                    self._port_methods.update(methods)
                continue

            for iface in matched_interfaces:
                kind = self.MESSAGE_BUS_INTERFACES.get(iface)
                if kind == "command":
                    self._commands[fqcn] = rel_path
                elif kind == "handler":
                    self._handlers[fqcn] = rel_path
                elif kind == "event":
                    self._events[fqcn] = rel_path
                elif kind == "listener":
                    self._listeners[fqcn] = rel_path

        for rel_path in self._all_php_files:
            full_path = os.path.join(self.root, rel_path)
            decl = read_php_declaration(full_path)
            if not decl:
                continue
            ns = self._extract_namespace(full_path)
            fqcn = ns + "\\" + decl["name"] if ns else decl["name"]
            if decl["extends"] and "Command" in decl["extends"] and "/Cli/" in rel_path:
                is_scheduled = False
                try:
                    with open(full_path, "r", errors="ignore") as f:
                        content = f.read(3000)
                    if re.search(
                        r"schedule|isDue|cron|every\w+\(", content, re.IGNORECASE
                    ):
                        is_scheduled = True
                except (IOError, OSError):
                    pass
                self._entry_points.append((fqcn, rel_path, "cli", is_scheduled))
            if rel_path.endswith("Controller.php") and (
                "Http/Controllers" in rel_path or "Presentation/Api" in rel_path
            ):
                self._entry_points.append((fqcn, rel_path, "ctrl", False))
            if "/Infrastructure/" in rel_path and decl["implements"]:
                self._adapters[fqcn] = rel_path
            if decl["extends"] and (
                "Client" in decl["extends"]
                or "GuzzleHttp" in self._read_imports(full_path)
            ):
                self._http_clients[fqcn] = rel_path

        print(
            f"  Fallback discovery: {len(self._commands)} commands, {len(self._handlers)} handlers",
            file=sys.stderr,
        )

    def _extract_namespace(self, filepath):
        """Extract PHP namespace from a file."""
        try:
            with open(filepath, "r", errors="ignore") as f:
                content = f.read(3000)
        except (IOError, OSError):
            return ""
        m = re.search(r"namespace\s+([^;]+);", content)
        return m.group(1) if m else ""

    def _extract_methods(self, filepath):
        """Extract method names from an interface file."""
        try:
            with open(filepath, "r", errors="ignore") as f:
                content = f.read(5000)
        except (IOError, OSError):
            return []
        return rx_all(r"function\s+(\w+)\s*\(", content)

    def _read_imports(self, filepath):
        """Read use/import statements from a PHP file."""
        try:
            with open(filepath, "r", errors="ignore") as f:
                content = f.read(3000)
        except (IOError, OSError):
            return ""
        return content

    # -----------------------------------------------------------------------
    # Graph queries
    # -----------------------------------------------------------------------

    # -----------------------------------------------------------------------
    # PHP source analysis (for call-chain tracing)
    # -----------------------------------------------------------------------

    def _run_ast_grep(self, filepath, patterns_config):
        """Run ast-grep for configured dispatch patterns.

        patterns_config: list of [method_name, mode] pairs, e.g.
                        [['dispatchSync', 'sync'], ['dispatchAsync', 'async']]
        Builds ast-grep pattern: $$$->{method}($$$)
        Returns deduplicated list of [(command_name, mode), ...].
        """
        results = []
        full_path = os.path.join(self.root, filepath)
        for entry in patterns_config:
            method = entry[0] if isinstance(entry, (list, tuple)) else entry
            mode = (
                entry[1]
                if isinstance(entry, (list, tuple)) and len(entry) > 1
                else "async"
            )
            pattern = f"$$$->{method}($$$)"
            try:
                result = subprocess.run(
                    ["sg", "run", "-p", pattern, "-l", "php", "--json", full_path],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                if result.returncode not in (0, 1) or not result.stdout.strip():
                    continue
                matches = json.loads(result.stdout)
                for m in matches:
                    cmd = self._extract_command_name(m.get("text", ""))
                    if cmd:
                        results.append((cmd, mode))
            except (FileNotFoundError, json.JSONDecodeError, subprocess.TimeoutExpired):
                continue
        seen = set()
        return [(c, m) for c, m in results if not (c in seen or seen.add(c))]

    def find_dispatch_patterns(self, filepath):
        """Find dispatch calls in a PHP file using ast-grep (AST-level matching)."""
        return self._run_ast_grep(filepath, self._dispatch_patterns)

    def _extract_command_name(self, text):
        """Extract the class name after 'new' keyword in a dispatch call."""
        m = re.search(r"new\s+(\w+)\s*\(", text)
        return m.group(1) if m else ""

    def find_handler_code(self, handler_filepath):
        """Read handler source and extract Port calls and sub-command dispatches.

        Captures ALL method calls that match any known port interface method,
        not just $this->erp->method() — works for any injected port.
        """
        try:
            with open(
                os.path.join(self.root, handler_filepath), "r", errors="ignore"
            ) as f:
                content = f.read()
        except (IOError, OSError):
            return [], []
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
        content = re.sub(r"//.*", "", content)

        # Port method calls: any $this->xxx->method() where method is a known port method
        port_calls = []
        if self._port_methods:
            for m in re.finditer(r"\$this->(\w+)\s*->\s*(\w+)\s*\(", content):
                method = m.group(2)
                if (
                    method in self._port_methods
                    and not method.startswith("dispatch")
                    and method
                    not in (
                        "__construct",
                        "__invoke",
                        "__toString",
                    )
                ):
                    port_calls.append(method)
        else:
            # Fallback: legacy heuristic (var name ends in port/adapter)
            for m in re.finditer(r"\$this->(\w+)\s*->\s*(\w+)\s*\(", content):
                var = m.group(1).lower()
                method = m.group(2)
                if (
                    var in ("erp", "erpport", "port")
                    or var.endswith("port")
                    or var.endswith("adapter")
                ):
                    if not method.startswith("dispatch") and method not in (
                        "__construct",
                        "__invoke",
                    ):
                        port_calls.append(method)

        # Sub-command dispatches — use ast-grep with configured dispatch patterns
        sub_commands = self._run_ast_grep(handler_filepath, self._dispatch_patterns)

        return port_calls, sub_commands

    def find_adapter_method_for_port(self, port_method):
        """Find adapter method by reading Infrastructure files for the method definition."""
        for fqcn, fpath in self._adapters.items():
            try:
                full = os.path.join(self.root, fpath)
                filesize = os.path.getsize(full)
                # Read enough of the file — methods can be deep in large files
                with open(full, "r", errors="ignore") as f:
                    content = f.read(min(filesize, 30000))
                if re.search(
                    r"function\s+" + re.escape(port_method) + r"\s*\(", content
                ):
                    return fqcn, fpath, port_method
            except (IOError, OSError):
                pass
        return None, None, None

    def find_http_calls_in_adapter(self, fpath):
        """Find HTTP client method calls in an adapter file."""
        try:
            with open(os.path.join(self.root, fpath), "r", errors="ignore") as f:
                content = f.read()
        except (IOError, OSError):
            return []
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
        content = re.sub(r"//.*", "", content)

        calls = []
        methods = set()
        for m in re.finditer(r"Client\s*->\s*(\w+)\s*\(", content):
            if m.group(1) not in methods:
                methods.add(m.group(1))
                calls.append(m.group(1))
        return calls

    def resolve_command_handler(self, command_name):
        """Find handler for a command by naming convention."""
        handler_name = command_name + "Handler"
        for fqcn, fpath in self._handlers.items():
            if fqcn.endswith("\\" + handler_name) or fqcn.endswith("/" + handler_name):
                return fqcn, fpath
        # Fallback: search all PHP files for the handler class
        handler_file = os.path.join(self.root, "**", handler_name + ".php")
        for rel_path in self._all_php_files:
            if rel_path.endswith("/" + handler_name + ".php"):
                decl = read_php_declaration(os.path.join(self.root, rel_path))
                if decl and decl["name"] == handler_name:
                    ns = self._extract_namespace(os.path.join(self.root, rel_path))
                    return ns + "\\" + handler_name if ns else handler_name, rel_path
        return "", ""

    def resolve_query_handler(self, query_name):
        """Find the handler for a query by name."""
        handler_name = query_name + "Handler"
        for fqcn, fpath in self._query_handlers.items():
            if fqcn.endswith("\\" + handler_name) or fqcn.endswith("/" + handler_name):
                return fqcn, fpath
        # Fallback: search all PHP files
        for rel_path in self._all_php_files:
            if rel_path.endswith("/" + handler_name + ".php"):
                decl = read_php_declaration(os.path.join(self.root, rel_path))
                if decl and decl["name"] == handler_name:
                    ns = self._extract_namespace(os.path.join(self.root, rel_path))
                    return ns + "\\" + handler_name if ns else handler_name, rel_path
        return "", ""

    def find_event_dispatches_in_file(self, fpath):
        """Find events dispatched in a file: $this->eventDispatcher->dispatch(new EventName(...))."""
        try:
            with open(os.path.join(self.root, fpath), "r", errors="ignore") as f:
                content = f.read()
        except (IOError, OSError):
            return []
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
        content = re.sub(r"//.*", "", content)
        events = []
        for m in re.finditer(r"dispatch\s*\(\s*new\s+(\w+)\s*\(", content):
            events.append(m.group(1))
        return events

    def find_http_calls_in_adapter_method(self, adapter_fpath, port_method):
        """Find HTTP client calls within the specific adapter method that implements port_method.

        Uses line-by-line brace counting to correctly scope the method body.
        """
        try:
            with open(
                os.path.join(self.root, adapter_fpath), "r", errors="ignore"
            ) as f:
                content = f.read()
        except (IOError, OSError):
            return []
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
        content = re.sub(r"//.*", "", content)

        # Find the method definition line
        lines = content.split("\n")
        method_start = -1
        for i, line in enumerate(lines):
            if re.search(r"function\s+" + re.escape(port_method) + r"\s*\(", line):
                method_start = i
                break
        if method_start < 0:
            return []

        # Find the opening brace after the method definition
        body_start = -1
        for i in range(method_start, len(lines)):
            brace_pos = lines[i].find("{")
            if brace_pos >= 0:
                body_start = i
                break
        if body_start < 0:
            return []

        # Count braces to find the matching closing brace
        depth = 0
        in_body = False
        body_end = len(lines)
        for i in range(body_start, len(lines)):
            for ch in lines[i]:
                if ch == "{":
                    depth += 1
                    in_body = True
                elif ch == "}":
                    depth -= 1
                    if in_body and depth == 0:
                        body_end = i + 1  # include this line
                        break
            if body_end < len(lines):
                break

        method_lines = lines[body_start:body_end]
        method_body = "\n".join(method_lines)

        # Find client calls within this method body
        calls = []
        methods = set()
        for m in re.finditer(r"Client\s*->\s*(\w+)\s*\(", method_body):
            if m.group(1) not in methods:
                methods.add(m.group(1))
                calls.append(m.group(1))
        return calls


# ---------------------------------------------------------------------------
# JSON builder (unchanged)
# ---------------------------------------------------------------------------


class UseCaseMapBuilder:
    """Builds the UseCaseMap JSON structure from scanned codebase data."""

    LAYER_LABELS = {
        "cli": "CLI Command",
        "ctrl": "HTTP Controller",
        "uc": "Component",
        "handler": "CommandHandler",
        "query": "Query",
        "qhandler": "QueryHandler",
        "port": "Port",
        "adapter": "Adapter",
        "http": "HTTP Client",
        "event": "Domain Event",
        "listnr": "Listener",
        "cb": "Callback Handler",
        "indirect": "Direct Call",
    }

    def __init__(self, scanner):
        self.s = scanner
        self.flows = []

    def build(self, title="", subtitle=""):
        if not title:
            title = "GET-E Core: Architecture Overview"
        if not subtitle:
            subtitle = (
                "Auto-generated use-case map from graphify + PHP declaration analysis"
            )

        for fqcn, fpath, kind, is_scheduled in self.s._entry_points:
            self._process_entry_point(fqcn, fpath, kind, is_scheduled)

        # Process callback flows
        self._process_callback_flows()

        sections = self._group_into_sections()
        return {"$schema": "", "title": title, "subtitle": subtitle, "items": sections}

    def _process_entry_point(self, fqcn, fpath, kind, is_scheduled):
        if self.s.component and not self.s._matches_component(fpath):
            return

        dispatch_patterns = self.s.find_dispatch_patterns(fpath)
        if not dispatch_patterns:
            if kind == "ctrl":
                return
            self._build_bypass_flow(fqcn, fpath, kind, is_scheduled)
            return

        flow_columns = OrderedDict()

        ns = self.s._extract_namespace(os.path.join(self.s.root, fpath))
        _, cls = os.path.split(fpath)
        cls = cls.replace(".php", "")
        ep_color = kind
        ep_info = ns if kind in ("cli", "ctrl") else ""

        # Listener entry points: show Listener::method with event info
        if kind == "listnr":
            listener_meta = self.s._listener_entries.get(fqcn, {})
            method = listener_meta.get("method", "handle")
            event_fqcn = listener_meta.get("event_fqcn", "")
            cls = cls + "::" + method
            ep_info = fqcn + "\n" + event_fqcn

        flow_columns["ep"] = self._make_column(
            self.LAYER_LABELS.get(ep_color, ep_color),
            ep_color,
            [{"title": cls, "info": ep_info, "color": ep_color, "type": "unit"}],
        )

        uc_items = []
        self._has_erp_in_current_flow = False
        for cmd_name, dispatch_mode in dispatch_patterns:
            # Check if this is a query vs command
            is_query = any(cmd_name == q.split("\\")[-1] for q in self.s._queries)
            uc_color = "query" if is_query else "uc"
            hdl_color = "qhandler" if is_query else "handler"
            if is_query:
                dispatch_mode = "sync"

            handler_fqcn, handler_fpath = self.s.resolve_command_handler(cmd_name)
            # If not found as a command, check if it's a query
            if not handler_fpath:
                handler_fqcn, handler_fpath = self.s.resolve_query_handler(cmd_name)
            port_calls = []
            sub_commands = []

            if handler_fpath:
                port_calls, sub_commands = self.s.find_handler_code(handler_fpath)
                if port_calls:
                    self._has_erp_in_current_flow = True

            handler_ns = ""
            handler_cls = cmd_name + ("Handler" if not is_query else "Handler")
            if handler_fqcn:
                parts = handler_fqcn.split("\\")
                handler_cls = parts[-1] if parts else handler_cls
                handler_ns = "\\".join(parts[:-1]) if len(parts) > 1 else ""

            handler_info = handler_ns + "\\" + handler_cls if handler_ns else ""
            if port_calls:
                handler_info += "\n" + "\n".join(
                    "- $this->erp->" + c + "()" for c in port_calls
                )

            uc_item = self._make_uc_item(
                cmd_name,
                handler_cls,
                handler_info,
                dispatch_mode,
                cmd_color=uc_color,
                hdl_color=hdl_color,
            )

            if sub_commands:
                sub_items = self._build_sub_items(sub_commands, 1)
                if sub_items:
                    # Recurse to collect ERP flag from nested items
                    def _collect_erp(items_list):
                        for it in items_list:
                            h = it.get("handler", {})
                            if "$this->erp->" in h.get("info", ""):
                                self._has_erp_in_current_flow = True
                            if "items" in it:
                                _collect_erp(it["items"])

                    _collect_erp(sub_items)
                uc_item["items"] = sub_items

            uc_items.append(uc_item)

        flow_columns["uc"] = self._make_column(
            "Component" if len(uc_items) == 1 else "Component",
            "uc",
            uc_items,
        )

        if self._has_erp_in_current_flow:
            all_port_calls = set()

            def _collect_port_calls(items):
                for it in items:
                    if "handler" in it:
                        hi = it["handler"].get("info", "")
                        pc = rx_all(r"\$this->erp->(\w+)\(\)", hi)
                        all_port_calls.update(pc)
                    if "items" in it:
                        _collect_port_calls(it["items"])

            _collect_port_calls(uc_items)

            if all_port_calls:
                port_items = []
                adapter_items = []
                http_items = []
                for pm in sorted(all_port_calls):
                    port_items.append(
                        {
                            "title": f"Erp::{pm}()",
                            "info": "App\\Core\\Port\\Erp",
                            "color": "port",
                            "type": "unit",
                        },
                    )
                    adapter_fqcn, adapter_fpath, _ = (
                        self.s.find_adapter_method_for_port(pm)
                    )
                    if adapter_fpath:
                        adapter_ns = self.s._extract_namespace(
                            os.path.join(self.s.root, adapter_fpath)
                        )
                        _, adapter_cls = os.path.split(adapter_fpath)
                        adapter_cls = adapter_cls.replace(".php", "")
                        http_calls = self.s.find_http_calls_in_adapter_method(
                            adapter_fpath, pm
                        )
                        adapter_info = (
                            adapter_ns + "\\" + adapter_cls if adapter_ns else ""
                        )
                        if http_calls:
                            adapter_info += "\n" + "\n".join(
                                "- " + c for c in http_calls
                            )
                        adapter_items.append(
                            {
                                "title": f"{adapter_cls}::{pm}()",
                                "info": adapter_info,
                                "color": "adapter",
                                "type": "unit",
                            }
                        )
                        if http_calls:
                            http_client_name = "NetsuiteClient"
                            http_client_fqcn = ""
                            try:
                                _raw = open(
                                    os.path.join(self.s.root, adapter_fpath),
                                    "r",
                                    errors="ignore",
                                ).read(5000)
                                for _u in re.finditer(r"use\s+([^;]+Client);", _raw):
                                    http_client_fqcn = _u.group(1).strip()
                                    if "HttpClient" in _u.group(1):
                                        break
                                if http_client_fqcn:
                                    http_client_name = http_client_fqcn.split("\\")[-1]
                            except (IOError, OSError):
                                pass
                            http_info = http_client_fqcn if http_client_fqcn else ""
                            if http_calls:
                                http_info += "\n" + "\n".join(
                                    "- " + c for c in http_calls
                                )
                            http_items.append(
                                {
                                    "title": http_client_name,
                                    "info": http_info,
                                    "color": "http",
                                    "type": "unit",
                                }
                            )
                if port_items:
                    flow_columns["port"] = self._make_column("Port", "port", port_items)
                if adapter_items:
                    seen = set()
                    ua = []
                    for a in adapter_items:
                        if a["title"] not in seen:
                            seen.add(a["title"])
                            ua.append(a)
                    flow_columns["adapter"] = self._make_column(
                        "Adapter", "adapter", ua
                    )
                if http_items:
                    seen = set()
                    uh = []
                    for h in http_items:
                        if h["title"] not in seen:
                            seen.add(h["title"])
                            uh.append(h)
                    flow_columns["http"] = self._make_column("HTTP Client", "http", uh)

        # Build flow title
        ns = self.s._extract_namespace(os.path.join(self.s.root, fpath))
        _, cls = os.path.split(fpath)
        cls = cls.replace(".php", "")
        cmd_signatures = ", ".join(c for c, _ in dispatch_patterns)
        flow_title = f"{cls} - {cmd_signatures}"
        self.flows.append(
            {
                "title": flow_title,
                "columns": list(flow_columns.values()),
                "is_scheduled": is_scheduled,
                "kind": kind,
                "_ns": ns,
            }
        )

    def _build_bypass_flow(self, fqcn, fpath, kind, is_scheduled):
        ns = self.s._extract_namespace(os.path.join(self.s.root, fpath))
        _, cls = os.path.split(fpath)
        cls = cls.replace(".php", "")
        ep_info = ns if kind in ("cli", "ctrl") else ""
        if kind == "listnr":
            meta = self.s._listener_entries.get(fqcn, {})
            method = meta.get("method", "handle")
            event_fqcn = meta.get("event_fqcn", "")
            cls = cls + "::" + method
            ep_info = fqcn + "\n" + event_fqcn
        columns = [
            self._make_column(
                self.LAYER_LABELS.get(kind, kind),
                kind,
                [{"title": cls, "info": ep_info, "color": kind, "type": "unit"}],
            )
        ]
        self.flows.append(
            {
                "title": cls,
                "columns": columns,
                "is_scheduled": is_scheduled,
                "kind": kind,
                "_ns": ns,
            }
        )

    def _group_into_sections(self):
        # Sort flows by kind, then by namespace within each kind
        cli_flows = sorted(
            [f for f in self.flows if f["kind"] == "cli"],
            key=lambda f: f.get("_ns", ""),
        )
        ctrl_flows = sorted(
            [f for f in self.flows if f["kind"] == "ctrl"],
            key=lambda f: f.get("_ns", ""),
        )
        listnr_flows = sorted(
            [f for f in self.flows if f["kind"] == "listnr"],
            key=lambda f: f.get("_ns", ""),
        )
        cb_flows = [f for f in self.flows if f["kind"] == "cb"]

        sections = OrderedDict()
        if cli_flows:
            sections["Cli commands"] = cli_flows
        if ctrl_flows:
            sections["Http controllers"] = ctrl_flows
        if cb_flows:
            sections["Callbacks"] = cb_flows
        if listnr_flows:
            sections["Listeners"] = listnr_flows

        result = []
        flow_num = 0
        sec_num = 0
        for sec_name, sec_flows in sections.items():
            sec_num += 1
            subs = []
            for i, flow in enumerate(sec_flows):
                flow_num += 1
                subs.append(
                    {
                        "title": f"{sec_num}.{i + 1} {flow['title']}",
                        "items": flow["columns"],
                    }
                )
            result.append({"title": f"{sec_num}. {sec_name}", "items": subs})
        return result

    def _make_column(self, title, color, items):
        return {"title": title, "color": color, "items": items}

    def _make_uc_item(
        self,
        cmd_name,
        handler_cls,
        handler_info,
        dispatch_mode,
        indentation=0,
        cmd_color="uc",
        hdl_color="handler",
    ):
        if cmd_color == "query":
            primary_key = "query"
            outer_type = "query"
            sub_type = "query"
            hdl_type = ""
        elif cmd_color == "event":
            primary_key = "event"
            outer_type = "event"
            sub_type = "event"
            hdl_type = ""
        elif cmd_color == "listnr":
            primary_key = "listener"
            outer_type = "event-listener"
            sub_type = "event-listener"
            hdl_type = ""
        else:
            primary_key = "command"
            outer_type = "use-case"
            sub_type = "command"
            hdl_type = "command-handler"
        item = {
            "title": cmd_name,
            "color": cmd_color,
            "type": outer_type,
            primary_key: {
                "title": cmd_name,
                "info": "",
                "color": cmd_color,
                "type": sub_type,
            },
        }
        if hdl_type and cmd_color != "event":
            item["handler"] = {
                "title": handler_cls or cmd_name + "Handler",
                "info": handler_info,
                "color": hdl_color,
                "type": hdl_type,
            }
        item["dispatchMode"] = dispatch_mode
        if indentation:
            item["indentation"] = indentation
        return item

    def _item_style(self, name):
        is_query = any(name == q.split("\\")[-1] for q in self.s._queries)
        is_event = any(name == e.split("\\")[-1] for e in self.s._events)
        if is_query:
            return ("query", "qhandler", "sync")
        if is_event:
            return ("event", "", "async")
        return ("uc", "handler", "")

    def _build_sub_items(self, sub_commands, depth=1, _visited=None):
        if _visited is None:
            _visited = set()
        items = []
        for sub_cmd, sub_mode in sub_commands:
            if sub_cmd in _visited:
                continue
            if depth > 10:
                continue
            s_cmd_color, s_hdl_color, s_forced_mode = self._item_style(sub_cmd)
            s_mode = s_forced_mode or sub_mode
            _visited.add(sub_cmd)
            s_handler_fqcn, s_handler_fpath = self.s.resolve_command_handler(sub_cmd)
            s_port_calls, s_deeper_subs = [], []
            if s_handler_fpath:
                s_port_calls, s_deeper_subs = self.s.find_handler_code(s_handler_fpath)
                if s_port_calls:
                    self._has_erp_in_current_flow = True
            s_handler_cls = sub_cmd + "Handler"
            s_handler_ns = ""
            if s_handler_fqcn:
                parts = s_handler_fqcn.split("\\")
                s_handler_cls = parts[-1]
                s_handler_ns = "\\".join(parts[:-1]) if len(parts) > 1 else ""
            s_handler_info = s_handler_ns + "\\" + s_handler_cls if s_handler_ns else ""
            if s_port_calls:
                s_handler_info += "\n" + "\n".join(
                    "- $this->erp->" + c + "()" for c in s_port_calls
                )
            sub_item = self._make_uc_item(
                sub_cmd,
                s_handler_cls,
                s_handler_info,
                s_mode,
                indentation=depth,
                cmd_color=s_cmd_color,
                hdl_color=s_hdl_color,
            )
            if s_deeper_subs:
                sub_item["items"] = self._build_sub_items(
                    s_deeper_subs, depth + 1, _visited
                )
            items.append(sub_item)
        return items

    def _process_callback_flows(self):
        for cb_fqcn, cb_fpath in self.s._callback_handlers.items():
            events_dispatched = self.s.find_event_dispatches_in_file(cb_fpath)
            if not events_dispatched:
                continue
            for event_name in events_dispatched:
                event_fqcn = ""
                for ev_fqcn in self.s._events:
                    if ev_fqcn.endswith("\\" + event_name):
                        event_fqcn = ev_fqcn
                        break
                if not event_fqcn:
                    continue
                listeners = [
                    l
                    for l in self.s._listeners
                    if self._listener_handles_event(l, event_fqcn)
                ]
                flow_columns = OrderedDict()
                ns = self.s._extract_namespace(os.path.join(self.s.root, cb_fpath))
                _, cls = os.path.split(cb_fpath)
                cls = cls.replace(".php", "")
                flow_columns["cb"] = self._make_column(
                    "Callback Handler",
                    "cb",
                    [
                        {
                            "title": cls + "::handle()",
                            "info": ns or "",
                            "color": "cb",
                            "type": "unit",
                        }
                    ],
                )
                _, ev_cls = os.path.split(event_fqcn.replace("\\", "/"))
                flow_columns["event"] = self._make_column(
                    "Domain Event",
                    "event",
                    [
                        {
                            "title": ev_cls or event_name,
                            "info": event_fqcn,
                            "color": "event",
                            "type": "event",
                        }
                    ],
                )
                for listener_fqcn in listeners:
                    listener_file = self.s._listeners.get(listener_fqcn, "")
                    if not listener_file:
                        continue
                    _, l_cls = os.path.split(listener_file)
                    l_cls = l_cls.replace(".php", "")
                    flow_columns["listnr"] = self._make_column(
                        "Listener",
                        "listnr",
                        [
                            {
                                "title": l_cls,
                                "info": listener_fqcn,
                                "color": "listnr",
                                "type": "event-listener",
                            }
                        ],
                    )
                    listener_commands = self.s.find_dispatch_patterns(listener_file)
                    uc_items = []
                    self._has_erp_in_current_flow = False
                    for cmd_name, dispatch_mode in listener_commands:
                        handler_fqcn, handler_fpath = self.s.resolve_command_handler(
                            cmd_name
                        )
                        port_calls = []
                        if handler_fpath:
                            port_calls, _ = self.s.find_handler_code(handler_fpath)
                            if port_calls:
                                self._has_erp_in_current_flow = True
                        handler_cls = cmd_name + "Handler"
                        handler_ns = ""
                        if handler_fqcn:
                            parts = handler_fqcn.split("\\")
                            handler_cls = parts[-1]
                            handler_ns = "\\".join(parts[:-1]) if len(parts) > 1 else ""
                        handler_info = (
                            handler_ns + "\\" + handler_cls if handler_ns else ""
                        )
                        if port_calls:
                            handler_info += "\n" + "\n".join(
                                "- $this->erp->" + c + "()" for c in port_calls
                            )
                        uc_items.append(
                            self._make_uc_item(
                                cmd_name,
                                handler_cls,
                                handler_info,
                                dispatch_mode,
                            )
                        )
                    if uc_items:
                        flow_columns["uc"] = self._make_column(
                            "Component", "uc", uc_items
                        )
                    if self._has_erp_in_current_flow:
                        all_calls = set()
                        for uc in uc_items:
                            hi = uc["handler"].get("info", "")
                            pc = rx_all(r"\$this->erp->(\w+)\(\)", hi)
                            all_calls.update(pc)
                        if all_calls:
                            port_items = []
                            adapter_items = []
                            http_items = []
                            for pm in sorted(all_calls):
                                port_items.append(
                                    {
                                        "title": f"Erp::{pm}()",
                                        "info": "App\\Core\\Port\\Erp",
                                        "color": "port",
                                        "type": "unit",
                                    }
                                )
                                afqcn, afpath, _ = self.s.find_adapter_method_for_port(
                                    pm
                                )
                                if afpath:
                                    _, acls = os.path.split(afpath)
                                    acls = acls.replace(".php", "")
                                    an = self.s._extract_namespace(
                                        os.path.join(self.s.root, afpath)
                                    )
                                    hc = self.s.find_http_calls_in_adapter_method(
                                        afpath, pm
                                    )
                                    ai = an + "\\" + acls if an else ""
                                    if hc:
                                        ai += "\n" + "\n".join("- " + c for c in hc)
                                    adapter_items.append(
                                        {
                                            "title": f"{acls}::{pm}()",
                                            "info": ai,
                                            "color": "adapter",
                                            "type": "unit",
                                        }
                                    )
                                    if hc:
                                        http_items.append(
                                            {
                                                "title": "NetsuiteClient",
                                                "info": "\n".join("- " + c for c in hc),
                                                "color": "http",
                                                "type": "unit",
                                            }
                                        )
                            if port_items:
                                flow_columns["port"] = self._make_column(
                                    "Port", "port", port_items
                                )
                            if adapter_items:
                                flow_columns["adapter"] = self._make_column(
                                    "Adapter", "adapter", adapter_items
                                )
                            if http_items:
                                flow_columns["http"] = self._make_column(
                                    "HTTP Client", "http", http_items
                                )
                cb_cls = cls
                flow_title = f"EVENT = {event_name} - {cb_cls}"
                self.flows.append(
                    {
                        "title": flow_title,
                        "columns": list(flow_columns.values()),
                        "is_scheduled": False,
                        "kind": "cb",
                        "_ns": ns,
                    }
                )

    def _listener_handles_event(self, listener_fqcn, event_fqcn):
        listener_file = self.s._listeners.get(listener_fqcn, "")
        if not listener_file:
            return False
        try:
            with open(
                os.path.join(self.s.root, listener_file), "r", errors="ignore"
            ) as f:
                content = f.read(8000)
            event_short = event_fqcn.split("\\")[-1]
            return event_short in content or event_fqcn in content
        except (IOError, OSError):
            return False


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate use-case-map JSON from PHP codebase"
    )
    parser.add_argument(
        "--project-root", "-r", default=".", help="PHP project root directory"
    )
    parser.add_argument(
        "--output", "-o", default="", help="Output file path (default: stdout)"
    )
    parser.add_argument(
        "--copy-visualizer",
        default="",
        help="Copy use-case-map-app.html visualizer to the specified destination path",
    )
    parser.add_argument(
        "--component",
        "-c",
        default="",
        help="Filter to a specific component (e.g. Billing)",
    )
    parser.add_argument("--title", "-t", default="", help="Diagram title")
    parser.add_argument("--subtitle", "-s", default="", help="Diagram subtitle")
    parser.add_argument(
        "--arch-config",
        default="",
        help="Architecture config file (PHP array). Default: conf/php/structure-explicit-architecture.php",
    )
    parser.add_argument(
        "--http-client-types",
        default="",
        help="HTTP client base types config file (PHP array). Default: conf/php/http-clients-types.php",
    )
    parser.add_argument(
        "--dispatch-patterns",
        default="",
        help="Dispatch pattern config file (PHP array of {pattern, mode}). Default: conf/php/get-e-message-bus-dispatch-patterns.php",
    )
    args = parser.parse_args()

    project_root = os.path.abspath(args.project_root)
    if not os.path.isdir(project_root):
        print(f"Error: project root not found: {project_root}", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning: {project_root}", file=sys.stderr)
    if args.component:
        print(f"Component filter: {args.component}", file=sys.stderr)

    scanner = GraphScanner(
        project_root,
        component=args.component,
        arch_config_path=args.arch_config or None,
        http_client_types_path=args.http_client_types or None,
        dispatch_patterns_path=args.dispatch_patterns or None,
    )
    scanner.scan()

    builder = UseCaseMapBuilder(scanner)
    result = builder.build(
        title=args.title
        or f"GET-E Core: {args.component + ' ' if args.component else ''}Architecture",
        subtitle=args.subtitle
        or "Auto-generated from graphify knowledge graph + PHP declaration analysis",
    )

    output = json.dumps(result, indent=2, ensure_ascii=False)

    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Written: {args.output} ({len(output)} bytes)", file=sys.stderr)
    else:
        print(output)

    if args.copy_visualizer:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        src_path = os.path.join(script_dir, "ArchDocs", "use-case-map-app.html")
        dest_path = os.path.abspath(args.copy_visualizer)
        if not os.path.isfile(src_path):
            print(
                f"Error: visualizer source not found at {src_path}",
                file=sys.stderr,
            )
            sys.exit(1)
        dest_dir = os.path.dirname(dest_path)
        if dest_dir and not os.path.isdir(dest_dir):
            os.makedirs(dest_dir, exist_ok=True)
        shutil.copy2(src_path, dest_path)
        print(f"Copied visualizer to: {dest_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
