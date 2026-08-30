<?php

declare(strict_types=1);

namespace Gete\PokeParser\Infrastructure\PokeApi;

use Gete\PokeParser\Application\GrowthRateLevelProvider;
use Gete\PokeParser\Domain\GrowthRateLevel;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\Level;

final readonly class HttpGrowthRateLevelProvider implements GrowthRateLevelProvider
{
    public function __construct(private \Closure $httpGetter) {}

    public function fetchGrowthRateLevels(GrowthRateReference $reference): GrowthRateLevelTable
    {
        /** @var array{levels: array{level: int, experience: int}[]} $response */
        $response = json_decode(($this->httpGetter)($reference->value), true, 512, JSON_THROW_ON_ERROR);

        $levels = array_map(
            /** @param array{level: int, experience: int} $entry */
            fn(array $entry): GrowthRateLevel => new GrowthRateLevel(
                requiredExperience: $entry['experience'],
                level: new Level($entry['level']),
            ),
            $response['levels'],
        );

        usort(
            $levels,
            fn(GrowthRateLevel $a, GrowthRateLevel $b) => $a->requiredExperience <=> $b->requiredExperience,
        );

        return new GrowthRateLevelTable(...$levels);
    }
}