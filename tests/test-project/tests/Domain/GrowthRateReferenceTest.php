<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\GrowthRateReference;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\GrowthRateReference
 */
final class GrowthRateReferenceTest extends TestCase
{
    /** @test */
    public function it_stores_the_url_string(): void
    {
        $url = 'https://pokeapi.co/api/v2/growth-rate/medium/';
        $reference = new GrowthRateReference($url);

        self::assertSame($url, $reference->value);
    }

    /** @test */
    public function it_throws_an_exception_on_empty_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Growth rate reference cannot be empty');

        new GrowthRateReference('');
    }

    /** @test */
    public function it_throws_an_exception_on_whitespace_only_string(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        new GrowthRateReference('   ');
    }
}
