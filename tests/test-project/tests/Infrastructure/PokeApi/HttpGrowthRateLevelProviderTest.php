<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Infrastructure\PokeApi;

use Gete\PokeParser\Application\GrowthRateLevelProvider;
use Gete\PokeParser\Domain\GrowthRateLevel;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Infrastructure\PokeApi\HttpGrowthRateLevelProvider;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Infrastructure\PokeApi\HttpGrowthRateLevelProvider
 */
final class HttpGrowthRateLevelProviderTest extends TestCase
{
    private function createProviderWithCallable(callable $httpGetter): HttpGrowthRateLevelProvider
    {
        return new HttpGrowthRateLevelProvider(\Closure::fromCallable($httpGetter));
    }

    /** @test */
    public function testFetchGrowthRateLevelsReturnsSortedTable(): void
    {
        $responseJson = json_encode([
            'levels' => [
                ['level' => 6, 'experience' => 5000],
                ['level' => 1, 'experience' => 0],
                ['level' => 3, 'experience' => 1250],
                ['level' => 4, 'experience' => 2166],
                ['level' => 2, 'experience' => 583],
                ['level' => 5, 'experience' => 3333],
            ],
        ], JSON_THROW_ON_ERROR);

        $httpGetter = static fn(string $url): string => $responseJson;

        $provider = $this->createProviderWithCallable($httpGetter);
        $result = $provider->fetchGrowthRateLevels(new GrowthRateReference(
            'https://pokeapi.co/api/v2/growth-rate/3/',
        ));

        self::assertInstanceOf(GrowthRateLevelTable::class, $result);
        self::assertCount(6, $result->levels);

        $expectedLevels = [1, 2, 3, 4, 5, 6];
        foreach ($expectedLevels as $i => $expectedLevel) {
            self::assertSame($expectedLevel, $result->levels[$i]->level->value);
        }
    }

    /** @test */
    public function testThrowsOnMalformedJson(): void
    {
        $httpGetter = static fn(string $url): string => 'not json';

        $this->expectException(\JsonException::class);

        $provider = $this->createProviderWithCallable($httpGetter);
        $provider->fetchGrowthRateLevels(new GrowthRateReference(
            'https://pokeapi.co/api/v2/growth-rate/3/',
        ));
    }

    /** @test */
    public function testReturnsEmptyTableForNoLevels(): void
    {
        $responseJson = json_encode([
            'levels' => [],
        ], JSON_THROW_ON_ERROR);

        $httpGetter = static fn(string $url): string => $responseJson;

        $provider = $this->createProviderWithCallable($httpGetter);
        $result = $provider->fetchGrowthRateLevels(new GrowthRateReference(
            'https://pokeapi.co/api/v2/growth-rate/3/',
        ));

        self::assertInstanceOf(GrowthRateLevelTable::class, $result);
        self::assertSame([], $result->levels);
    }
}