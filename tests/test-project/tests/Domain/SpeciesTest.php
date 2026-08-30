<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\Species;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\Species
 */
final class SpeciesTest extends TestCase
{
    /** @test */
    public function it_stores_the_species_name(): void
    {
        $species = new Species('Pikachu');

        self::assertSame('Pikachu', $species->value);
    }

    /** @test */
    public function it_accepts_a_multi_word_species_name(): void
    {
        $species = new Species('Mime Jr.');

        self::assertSame('Mime Jr.', $species->value);
    }

    /** @test */
    public function it_throws_an_exception_on_empty_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Species cannot be empty');

        new Species('');
    }

    /** @test */
    public function it_throws_an_exception_on_whitespace_only_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        new Species('   ');
    }
}
