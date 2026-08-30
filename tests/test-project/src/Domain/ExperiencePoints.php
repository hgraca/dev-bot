<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class ExperiencePoints
{
    public readonly int $value;

    public function __construct(int $value)
    {
        if ($value < 0) {
            throw new \InvalidArgumentException('Experience points cannot be negative');
        }

        $this->value = $value;
    }
}
