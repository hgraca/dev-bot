<?php

declare(strict_types=1);

namespace Gete\PokeParser\Domain;

final class Pokemon
{
    public readonly PokemonName $name;
    public readonly ExperiencePoints $experience;
    public readonly Species $species;
    public readonly Level $level;

    public function __construct(
        PokemonName $name,
        ExperiencePoints $experience,
        Species $species,
        Level $level,
    ) {
        $this->name = $name;
        $this->experience = $experience;
        $this->species = $species;
        $this->level = $level;
    }
}
