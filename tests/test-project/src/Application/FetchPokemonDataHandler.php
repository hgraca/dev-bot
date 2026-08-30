<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use GetE\MessageBus\Port\QueryBus\QueryHandler;

/** @implements QueryHandler<FetchPokemonData> */
final readonly class FetchPokemonDataHandler implements QueryHandler
{
    public function __construct(private PokemonDataProvider $provider) {}

    public function __invoke(FetchPokemonData $query): PokemonDataResult
    {
        return $this->provider->fetchPokemonData($query->pokemonName);
    }
}