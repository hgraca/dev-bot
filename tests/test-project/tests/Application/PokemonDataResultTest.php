<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Application;

use Gete\PokeParser\Application\PokemonDataResult;
use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Domain\Species;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Application\PokemonDataResult
 */
final class PokemonDataResultTest extends TestCase
{
    private PokemonName $name;
    private Species $species;
    private GrowthRateReference $growthRateReference;
    private PokemonDataResult $result;

    protected function setUp(): void
    {
        parent::setUp();

        $this->name = new PokemonName('pikachu');
        $this->species = new Species('Pikachu');
        $this->growthRateReference = new GrowthRateReference('https://pokeapi.co/api/v2/growth-rate/medium/');
        $this->result = new PokemonDataResult(
            $this->name,
            112,
            $this->species,
            $this->growthRateReference,
        );
    }

    /** @test */
    public function it_stores_the_name(): void
    {
        self::assertSame($this->name, $this->result->name);
    }

    /** @test */
    public function it_stores_the_experience_as_primitive_int(): void
    {
        self::assertSame(112, $this->result->experience);
    }

    /** @test */
    public function it_stores_the_species(): void
    {
        self::assertSame($this->species, $this->result->species);
    }

    /** @test */
    public function it_stores_the_growth_rate_reference(): void
    {
        self::assertSame($this->growthRateReference, $this->result->growthRateReference);
    }

    /** @test */
    public function it_accepts_zero_experience(): void
    {
        $result = new PokemonDataResult(
            new PokemonName('magikarp'),
            0,
            new Species('Magikarp'),
            new GrowthRateReference('https://pokeapi.co/api/v2/growth-rate/slow/'),
        );

        self::assertSame(0, $result->experience);
    }

    /** @test */
    public function it_accepts_a_large_experience_value(): void
    {
        $result = new PokemonDataResult(
            new PokemonName('mewtwo'),
            999_999,
            new Species('Mewtwo'),
            new GrowthRateReference('https://pokeapi.co/api/v2/growth-rate/slow/'),
        );

        self::assertSame(999_999, $result->experience);
    }
}
