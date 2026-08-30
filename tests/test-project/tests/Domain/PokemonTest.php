<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\ExperiencePoints;
use Gete\PokeParser\Domain\Level;
use Gete\PokeParser\Domain\Pokemon;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Domain\Species;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\Pokemon
 */
final class PokemonTest extends TestCase
{
    private PokemonName $name;
    private ExperiencePoints $experience;
    private Species $species;
    private Level $level;
    private Pokemon $pokemon;

    protected function setUp(): void
    {
        parent::setUp();

        $this->name = new PokemonName('pikachu');
        $this->experience = new ExperiencePoints(112);
        $this->species = new Species('Pikachu');
        $this->level = new Level(16);
        $this->pokemon = new Pokemon($this->name, $this->experience, $this->species, $this->level);
    }

    /** @test */
    public function it_stores_the_name(): void
    {
        self::assertSame($this->name, $this->pokemon->name);
    }

    /** @test */
    public function it_stores_the_experience(): void
    {
        self::assertSame($this->experience, $this->pokemon->experience);
    }

    /** @test */
    public function it_stores_the_species(): void
    {
        self::assertSame($this->species, $this->pokemon->species);
    }

    /** @test */
    public function it_stores_the_level(): void
    {
        self::assertSame($this->level, $this->pokemon->level);
    }

    /** @test */
    public function it_accepts_different_pokemon_values(): void
    {
        $name = new PokemonName('bulbasaur');
        $experience = new ExperiencePoints(64);
        $species = new Species('Bulbasaur');
        $level = new Level(1);

        $pokemon = new Pokemon($name, $experience, $species, $level);

        self::assertSame($name, $pokemon->name);
        self::assertSame($experience, $pokemon->experience);
        self::assertSame($species, $pokemon->species);
        self::assertSame($level, $pokemon->level);
    }
}
