<?php
// =============================================================================
// conf/php/http-clients-types.php
// Base classes / interfaces whose extension or implementation marks a class
// as an HTTP client. The use-case-map tool renders classes matching any of
// these as "HTTP Client" units. Adjust to your project's HTTP client
// conventions (e.g. a port interface under app/Core/Port/).
// =============================================================================

return [
    'GuzzleHttp\\Client',
];
