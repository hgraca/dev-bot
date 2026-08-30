<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class GrowthRateLevelTable
{
    /** @var GrowthRateLevel[] */
    public readonly array $levels;

    public function __construct(GrowthRateLevel ...$levels)
    {
        $this->levels = $levels;
    }

    public function levelFor(int $experience): ?Level
    {
        if (empty($this->levels)) {
            return null;
        }

        $matched = null;

        foreach ($this->levels as $level) {
            if ($level->requiredExperience <= $experience) {
                $matched = $level->level;
            } else {
                break;
            }
        }

        return $matched;
    }
}
