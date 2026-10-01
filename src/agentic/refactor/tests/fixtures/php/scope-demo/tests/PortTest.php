<?php

declare(strict_types=1);

namespace Demo\Test;

use Demo\Port;

final class PortTest
{
    public function run(Port $port): void
    {
        $port->emit('hello');
    }
}
