<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class Level
{
    public readonly int $value;

    public function __construct(int $value)
    {
        if ($value < 1 || $value > 100) {
            throw new \InvalidArgumentException('Level must be between 1 and 100');
        }

        $this->value = $value;
    }
}
