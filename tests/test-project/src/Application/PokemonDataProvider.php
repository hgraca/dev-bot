<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use Gete\PokeParser\Domain\PokemonName;

interface PokemonDataProvider
{
    public function fetchPokemonData(PokemonName $name): PokemonDataResult;
}