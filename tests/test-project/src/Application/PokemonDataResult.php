<?php

declare(strict_types=1);

namespace Gete\PokeParser\Application;

use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Domain\Species;

final class PokemonDataResult
{
    public readonly PokemonName $name;
    public readonly int $experience;
    public readonly Species $species;
    public readonly GrowthRateReference $growthRateReference;

    public function __construct(
        PokemonName $name,
        int $experience,
        Species $species,
        GrowthRateReference $growthRateReference,
    ) {
        $this->name = $name;
        $this->experience = $experience;
        $this->species = $species;
        $this->growthRateReference = $growthRateReference;
    }
}
