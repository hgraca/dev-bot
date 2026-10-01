<?php

declare(strict_types=1);

namespace Demo;

final class Adapter implements Port
{
    public function emit(string $message): void
    {
    }
}
