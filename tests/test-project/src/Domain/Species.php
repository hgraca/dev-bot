<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class Species
{
    public readonly string $value;

    public function __construct(string $value)
    {
        if (trim($value) === '') {
            throw new \InvalidArgumentException('Species cannot be empty');
        }

        $this->value = $value;
    }
}
