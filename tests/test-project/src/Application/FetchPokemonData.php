<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use GetE\MessageBus\Port\QueryBus\Query;
use Gete\PokeParser\Domain\PokemonName;

/** @implements Query<PokemonDataResult> */
final readonly class FetchPokemonData implements Query
{
    public function __construct(public readonly PokemonName $pokemonName) {}
}