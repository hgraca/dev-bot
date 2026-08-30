<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Integration\PokeApi;

use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Infrastructure\PokeApi\HttpPokemonDataProvider
 * @covers \Gete\PokeParser\Infrastructure\PokeApi\HttpGrowthRateLevelProvider
 * @covers \Gete\PokeParser\Application\PokemonLevelService
 */
final class RunScriptTest extends TestCase
{
    /** @test */
    public function testProducesExpectedOutput(): void
    {
        $output = [];
        $returnCode = 0;

        exec(
            'php ' . escapeshellarg(__DIR__ . '/../../../bin/run.php') . ' ivysaur bulbasaur pikachu ditto',
            $output,
            $returnCode,
        );

        self::assertSame(0, $returnCode, 'Script should exit with code 0');

        $expected = [
            'ivysaur 142 ivysaur 5',
            'bulbasaur 64 bulbasaur 3',
            'pikachu 112 pikachu 4',
            'ditto 101 ditto 4',
        ];

        self::assertCount(count($expected), $output);
        self::assertSame($expected, $output);
    }

    /** @test */
    public function testProducesExpectedOutputForSinglePokemon(): void
    {
        $output = [];
        $returnCode = 0;

        exec(
            'php ' . escapeshellarg(__DIR__ . '/../../../bin/run.php') . ' ivysaur',
            $output,
            $returnCode,
        );

        self::assertSame(0, $returnCode);
        self::assertCount(1, $output);
        self::assertSame('ivysaur 142 ivysaur 5', $output[0]);
    }

    /** @test */
    public function testProducesExpectedOutputForEmptyInput(): void
    {
        $output = [];
        $returnCode = 0;

        exec(
            'php ' . escapeshellarg(__DIR__ . '/../../../bin/run.php') . '',
            $output,
            $returnCode,
        );

        self::assertSame(0, $returnCode);
        self::assertSame([], $output);
    }
}