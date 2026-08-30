<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use GetE\MessageBus\Adapter\Dummy\QueryDispatcher;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\Pokemon;
use Gete\PokeParser\Domain\PokemonName;

final readonly class PokemonLevelService
{
    public function __construct(private QueryDispatcher $queryDispatcher) {}

    /**
     * @param PokemonName ...$names
     * @return Pokemon[]
     */
    public function calculateLevels(PokemonName ...$names): array
    {
        $results = [];

        foreach ($names as $name) {
            /** @var PokemonDataResult $dataResult */
            $dataResult = $this->queryDispatcher->dispatch(new FetchPokemonData($name));
            /** @var GrowthRateLevelTable $levelTable */
            $levelTable = $this->queryDispatcher->dispatch(
                new FetchGrowthRateLevels($dataResult->growthRateReference),
            );
            $level = $levelTable->levelFor($dataResult->experience) ?? throw new \RuntimeException('No level found for experience');

            $results[] = new Pokemon(
                $dataResult->name,
                new \Gete\PokeParser\Domain\ExperiencePoints($dataResult->experience),
                $dataResult->species,
                $level,
            );
        }

        return $results;
    }
}