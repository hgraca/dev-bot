<?php

declare(strict_types=1);

namespace Demo;

final class UsesHelper
{
    public function run(): string
    {
        return demoHelper('x');
    }
}
