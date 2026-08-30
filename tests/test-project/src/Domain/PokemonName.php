<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class PokemonName
{
    public readonly string $value;

    public function __construct(string $value)
    {
        if (trim($value) === '') {
            throw new \InvalidArgumentException('Pokemon name cannot be empty');
        }

        $this->value = $value;
    }
}
