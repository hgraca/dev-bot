<?php
// =============================================================================
// conf/php/message-bus-dispatch-patterns.php
// Message-bus dispatch method conventions. Each entry is [method, mode] where
// mode is 'sync' or 'async'. The use-case-map tool runs ast-grep for
// `$obj-><method>(new Foo(...))` calls to trace command/query dispatches.
// Adjust to your message-bus dispatch method names.
// =============================================================================

return [
    ['dispatchSync', 'sync'],
    ['dispatchAsync', 'async'],
    ['dispatch', 'async'],
];
