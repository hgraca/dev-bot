<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use GetE\MessageBus\Port\QueryBus\QueryHandler;

/** @implements QueryHandler<FetchGrowthRateLevels> */
final readonly class FetchGrowthRateLevelsHandler implements QueryHandler
{
    public function __construct(private GrowthRateLevelProvider $provider) {}

    public function __invoke(FetchGrowthRateLevels $query): \Gete\PokeParser\Domain\GrowthRateLevelTable
    {
        return $this->provider->fetchGrowthRateLevels($query->reference);
    }
}