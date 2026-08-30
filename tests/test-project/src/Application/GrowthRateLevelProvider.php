<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\GrowthRateLevelTable;

interface GrowthRateLevelProvider
{
    public function fetchGrowthRateLevels(GrowthRateReference $reference): GrowthRateLevelTable;
}