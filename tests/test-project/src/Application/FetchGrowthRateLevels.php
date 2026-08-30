<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use GetE\MessageBus\Port\QueryBus\Query;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\GrowthRateReference;

/** @implements Query<GrowthRateLevelTable> */
final readonly class FetchGrowthRateLevels implements Query
{
    public function __construct(public readonly GrowthRateReference $reference) {}
}