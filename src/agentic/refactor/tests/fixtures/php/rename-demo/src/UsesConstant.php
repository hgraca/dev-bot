<?php

declare(strict_types=1);

namespace Demo;

final class UsesConstant
{
    public function run(): int
    {
        return DEMO_LIMIT;
    }
}
