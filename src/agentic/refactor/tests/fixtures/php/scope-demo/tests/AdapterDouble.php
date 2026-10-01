<?php

declare(strict_types=1);

namespace Demo\Test;

use Demo\Port;

final class AdapterDouble implements Port
{
    public function emit(string $message): void
    {
    }
}
