<?php

declare(strict_types=1);

namespace Demo;

final class UseGreeter
{
    public function run(): string
    {
        return (new Greeter())->greet('world');
    }
}
