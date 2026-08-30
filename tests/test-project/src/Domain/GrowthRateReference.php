<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class GrowthRateReference
{
    public readonly string $value;

    public function __construct(string $value)
    {
        if (trim($value) === '') {
            throw new \InvalidArgumentException('Growth rate reference cannot be empty');
        }

        $this->value = $value;
    }
}
