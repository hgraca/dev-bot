<?php
// =============================================================================
// conf/php/structure-explicit-architecture.php
// Directory layout for projects following explicit-architecture conventions
// (see the devbot:explicit-architecture skill). The use-case-map tool reads
// this to know where entry points, ports, adapters and callback handlers live.
//
// Paths are relative to the project root. Adjust to your project structure.
// =============================================================================

return [
    // Entry points: where CLI commands and HTTP controllers are discovered.
    'entry_points' => [
        'cli' => ['app/Presentation/Cli/'],
        'http' => ['app/Presentation/Api/', 'app/Presentation/Web/'],
    ],
    // Adapters: implementations of ports, typically under Infrastructure.
    'adapters' => [
        'directories' => ['app/Infrastructure/'],
    ],
    // Ports: interfaces the core depends on.
    'ports' => [
        'directories' => ['app/Core/Port/'],
    ],
    // Callback handlers: classes implementing this interface are treated as
    // event-dispatching callback entry points. Empty string disables the
    // feature (the default when no interface is configured).
    'callbacks' => [
        'interface' => '',
    ],
];
