<?php
// =============================================================================
// conf/php/message-bus-types.php
// Discovers message-bus types in a PHP codebase without a composer autoloader.
// The use-case-map tool feeds it a list of PHP file paths (one per line, on
// stdin) and reads JSON on stdout describing the discovered message-bus wiring:
//
//   {
//     "use-cases": { "<CmdFQCN>": "<HandlerFQCN>", ... },
//     "queries":   { "<QueryFQCN>": "<QueryHandlerFQCN>", ... },
//     "events":    { "<EventFQCN>": ["<ListenerFQCN>::handle", ...], ... }
//   }
//
// Naming conventions (matching the use-case-map skill):
//   - a class whose name ends with "Command" (or implements an interface
//     ending in "Command") is a command
//   - "CommandHandler" is its handler; "<Name>Command" pairs with
//     "<Name>CommandHandler"
//   - a class whose name ends with "Query" is a query, "<Name>QueryHandler"
//     handles it (always sync)
//   - a class whose name ends with "Event" is an event; listeners implement
//     "EventListener" / end with "Listener" and declare the event in their
//     method signature or docblock
//
// Usage: php message-bus-types.php <php_root> < files.txt
// =============================================================================

error_reporting(E_ALL & ~E_DEPRECATED & ~E_WARNING);

$phpRoot = $argv[1] ?? getcwd();

$files = [];
while (($line = fgets(STDIN)) !== false) {
    $line = trim($line);
    if ($line !== '') {
        $files[] = $line;
    }
}

// ── Declaration registry ────────────────────────────────────────────────────
// fqcn => ['file' => rel, 'name' => short, 'extends' => fqcn|null,
//          'implements' => fqcn[]]
$classes = [];

function _abs($name, $namespace): string {
    if (str_starts_with($name, '\\')) {
        return ltrim($name, '\\');
    }
    return $namespace ? $namespace . '\\' . $name : $name;
}

foreach ($files as $rel) {
    $full = $phpRoot . '/' . $rel;
    if (!is_file($full)) {
        continue;
    }
    $code = file_get_contents($full);
    if ($code === false) {
        continue;
    }
    // Strip comments so docblocks with "Event" don't pollute implements.
    $code = preg_replace('#/\*.*?\*/#s', '', $code);
    $code = preg_replace('#^\s*//.*$#m', '', $code);

    $namespace = '';
    if (preg_match('/namespace\s+([^;]+);/', $code, $m)) {
        $namespace = trim($m[1]);
    }

    // class/interface/abstract declarations with extends + implements
    if (preg_match_all(
        '/(?:(?:abstract\s+|final\s+)*)(?:class|interface|trait)\s+(\w+)'
            . '(?:\s+extends\s+([\\\\\w]+))?'
            . '(?:\s+implements\s+([^\{]+))?/',
        $code,
        $matches,
        PREG_SET_ORDER
    )) {
        foreach ($matches as $mm) {
            $name = $mm[1];
            $fqcn = $namespace ? $namespace . '\\' . $name : $name;
            $extends = isset($mm[2]) && trim($mm[2]) ? _abs($mm[2], $namespace) : null;
            $implements = [];
            if (isset($mm[3]) && trim($mm[3])) {
                foreach (preg_split('/\s*,\s*/', trim($mm[3])) as $iface) {
                    if ($iface !== '') {
                        $implements[] = _abs($iface, $namespace);
                    }
                }
            }
            if (!isset($classes[$fqcn])) {
                $classes[$fqcn] = [
                    'file' => $rel,
                    'name' => $name,
                    'extends' => $extends,
                    'implements' => $implements,
                ];
            }
        }
    }
}

// ── Short-name → FQCN index for interface matching ──────────────────────────
$shortIndex = [];
foreach ($classes as $fqcn => $info) {
    $shortIndex[$info['name']] = $fqcn;
}

// ── Classify ────────────────────────────────────────────────────────────────
$commands = [];       // fqcn => info
$queries = [];        // fqcn => info
$events = [];         // fqcn => info
$handlers = [];       // fqcn => info
$queryHandlers = [];  // fqcn => info
$listeners = [];      // fqcn => info

foreach ($classes as $fqcn => $info) {
    $name = $info['name'];
    // Presentation/ holds entry points (CLI commands, HTTP controllers), not
    // message-bus commands — skip them so they are not double-classified.
    if (str_contains($info['file'], '/Presentation/')) {
        continue;
    }
    $ifaces = array_map(fn($i) => $shortIndex[$i] ?? $i, $info['implements']);
    $matchesIface = function (string $suffix) use ($ifaces): bool {
        foreach ($ifaces as $i) {
            if (str_ends_with($i, $suffix)) {
                return true;
            }
        }
        return false;
    };

    if (str_ends_with($name, 'Command') || $matchesIface('Command')) {
        $commands[$fqcn] = $info;
    } elseif (str_ends_with($name, 'Query') || $matchesIface('Query')) {
        $queries[$fqcn] = $info;
    } elseif (str_ends_with($name, 'Event') || $matchesIface('Event')) {
        $events[$fqcn] = $info;
    }

    if (str_ends_with($name, 'QueryHandler') || $matchesIface('QueryHandler')) {
        $queryHandlers[$fqcn] = $info;
    } elseif (str_ends_with($name, 'CommandHandler') || $matchesIface('CommandHandler') || str_ends_with($name, 'Handler')) {
        $handlers[$fqcn] = $info;
    }

    if (str_ends_with($name, 'EventListener') || str_ends_with($name, 'Listener') || $matchesIface('EventListener')) {
        $listeners[$fqcn] = $info;
    }
}

// ── Pair commands → handlers by naming convention ───────────────────────────
$useCases = [];
foreach ($commands as $fqcn => $info) {
    // FooCommand ↔ FooCommandHandler (also accepts FooCommandHandler in any ns)
    $base = preg_replace('/Command$/', '', $info['name']);
    $want = $base . 'CommandHandler';
    foreach ($handlers as $hFqcn => $hInfo) {
        if ($hInfo['name'] === $want) {
            $useCases[$fqcn] = $hFqcn;
            break;
        }
    }
}

$queriesOut = [];
foreach ($queries as $fqcn => $info) {
    $base = preg_replace('/Query$/', '', $info['name']);
    $want = $base . 'QueryHandler';
    foreach ($queryHandlers as $hFqcn => $hInfo) {
        if ($hInfo['name'] === $want) {
            $queriesOut[$fqcn] = $hFqcn;
            break;
        }
    }
}

// ── Pair events → listeners ─────────────────────────────────────────────────
// A listener declares the event it handles when its short name starts with the
// event's base name (FooEvent ↔ FooListener/FooEventListener), or when the
// listener's file content mentions the event short name.
$eventsOut = [];
foreach ($events as $eFqcn => $eInfo) {
    $eBase = preg_replace('/Event$/', '', $eInfo['name']);
    $matched = [];
    foreach ($listeners as $lFqcn => $lInfo) {
        $lName = $lInfo['name'];
        $lBase = preg_replace('/(Event)?Listener$/', '', $lName);
        $related = str_starts_with($eBase, $lBase) || str_starts_with($lBase, $eBase);
        if ($related || str_contains($lBase, $eBase) || str_contains($eBase, $lBase)) {
            $matched[] = $lFqcn . '::handle';
        }
    }
    if ($matched) {
        $eventsOut[$eFqcn] = $matched;
    }
}

echo json_encode([
    'use-cases' => (object) $useCases,
    'queries' => (object) $queriesOut,
    'events' => (object) $eventsOut,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
