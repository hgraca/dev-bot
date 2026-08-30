#!/usr/bin/env php
<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/vendor/autoload.php';

use GetE\MessageBus\Adapter\Dummy\HandlerResolver;
use GetE\MessageBus\Adapter\Dummy\QueryDispatcher;
use Gete\PokeParser\Application\FetchGrowthRateLevels;
use Gete\PokeParser\Application\FetchGrowthRateLevelsHandler;
use Gete\PokeParser\Application\FetchPokemonData;
use Gete\PokeParser\Application\FetchPokemonDataHandler;
use Gete\PokeParser\Application\PokemonLevelService;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Infrastructure\PokeApi\HttpGrowthRateLevelProvider;
use Gete\PokeParser\Infrastructure\PokeApi\HttpPokemonDataProvider;

$httpGetter = static function (string $url): string {
    $stream = fopen($url, 'r');
    if ($stream === false) {
        throw new \RuntimeException("Failed to open URL: $url");
    }
    $result = stream_get_contents($stream);
    if ($result === false) {
        throw new \RuntimeException("Failed to read URL: $url");
    }
    return $result;
};

$pokemonDataProvider = new HttpPokemonDataProvider($httpGetter);
$growthRateLevelProvider = new HttpGrowthRateLevelProvider($httpGetter);

$handlerResolver = new class($pokemonDataProvider, $growthRateLevelProvider) implements HandlerResolver {
    public function __construct(
        private readonly HttpPokemonDataProvider $pokemonDataProvider,
        private readonly HttpGrowthRateLevelProvider $growthRateLevelProvider,
    ) {}

    public function resolve(string $handlerFqcn): object
    {
        return match ($handlerFqcn) {
            FetchPokemonDataHandler::class => new FetchPokemonDataHandler(
                $this->pokemonDataProvider,
            ),
            FetchGrowthRateLevelsHandler::class => new FetchGrowthRateLevelsHandler(
                $this->growthRateLevelProvider,
            ),
            default => throw new \RuntimeException("Unknown handler: $handlerFqcn"),
        };
    }
};

$queryDispatcher = new QueryDispatcher($handlerResolver);
$service = new PokemonLevelService($queryDispatcher);

$names = array_map(
    static fn(string $name): PokemonName => new PokemonName($name),
    array_slice($argv, 1),
);

$results = $service->calculateLevels(...$names);

$out = array_map(
    static fn(\Gete\PokeParser\Domain\Pokemon $p): string => sprintf(
        '%s %d %s %d',
        $p->name->value,
        $p->experience->value,
        $p->species->value,
        $p->level->value,
    ),
    $results,
);

echo implode("\n", $out);