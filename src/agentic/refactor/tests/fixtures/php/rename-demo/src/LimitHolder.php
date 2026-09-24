<?php

declare(strict_types=1);

namespace Demo;

final class LimitHolder
{
    public const DEMO_MAX = 10;

    public function read(): int
    {
        return self::DEMO_MAX;
    }

    public function legacyKey(): string
    {
        return 'demo_max_key';
    }
}
