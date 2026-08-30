<?php

declare(strict_types=1);

namespace Gete\PokeParser\Infrastructure\PokeApi;

use Gete\PokeParser\Application\PokemonDataProvider;
use Gete\PokeParser\Application\PokemonDataResult;
use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Domain\Species;

final readonly class HttpPokemonDataProvider implements PokemonDataProvider
{
    public function __construct(private \Closure $httpGetter) {}

    public function fetchPokemonData(PokemonName $name): PokemonDataResult
    {
        $url = "https://pokeapi.co/api/v2/pokemon/{$name->value}";
        /** @var array{base_experience: int, species: array{name: string, url: string}} $response */
        $response = json_decode(($this->httpGetter)($url), true, 512, JSON_THROW_ON_ERROR);

        $speciesUrl = $response['species']['url'];
        /** @var array{growth_rate: array{url: string}} $speciesResponse */
        $speciesResponse = json_decode(($this->httpGetter)($speciesUrl), true, 512, JSON_THROW_ON_ERROR);
        $growthRateUrl = $speciesResponse['growth_rate']['url'];

        return new PokemonDataResult(
            name: $name,
            experience: $response['base_experience'],
            species: new Species($response['species']['name']),
            growthRateReference: new GrowthRateReference($growthRateUrl),
        );
    }
}