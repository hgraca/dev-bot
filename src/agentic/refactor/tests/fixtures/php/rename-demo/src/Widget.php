<?php

declare(strict_types=1);

namespace Demo;

final class Widget
{
    public string $label = 'w';

    public static function make(): self
    {
        return new self();
    }
}
