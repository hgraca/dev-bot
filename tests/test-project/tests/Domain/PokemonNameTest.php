<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\PokemonName;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\PokemonName
 */
final class PokemonNameTest extends TestCase
{
    /** @test */
    public function it_stores_the_name_string(): void
    {
        $name = new PokemonName('pikachu');

        self::assertSame('pikachu', $name->value);
    }

    /** @test */
    public function it_accepts_a_name_with_spaces(): void
    {
        $name = new PokemonName('Mr. Mime');

        self::assertSame('Mr. Mime', $name->value);
    }

    /** @test */
    public function it_throws_an_exception_on_empty_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Pokemon name cannot be empty');

        new PokemonName('');
    }

    /** @test */
    public function it_throws_an_exception_on_whitespace_only_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        new PokemonName('   ');
    }
}
