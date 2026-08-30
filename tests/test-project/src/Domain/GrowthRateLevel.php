<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class GrowthRateLevel
{
    public readonly int $requiredExperience;
    public readonly Level $level;

    public function __construct(int $requiredExperience, Level $level)
    {
        $this->requiredExperience = $requiredExperience;
        $this->level = $level;
    }
}
