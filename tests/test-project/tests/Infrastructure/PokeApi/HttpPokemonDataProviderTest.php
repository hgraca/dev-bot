<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Infrastructure\PokeApi;

use Gete\PokeParser\Application\PokemonDataResult;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Infrastructure\PokeApi\HttpPokemonDataProvider;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Infrastructure\PokeApi\HttpPokemonDataProvider
 */
final class HttpPokemonDataProviderTest extends TestCase
{
    private function createProviderWithCallable(callable $httpGetter): HttpPokemonDataProvider
    {
        return new HttpPokemonDataProvider(\Closure::fromCallable($httpGetter));
    }

    /** @test */
    public function testFetchPokemonDataReturnsCorrectResult(): void
    {
        $pokemonResponse = json_encode([
            'base_experience' => 142,
            'species' => [
                'name' => 'ivysaur',
                'url' => 'https://pokeapi.co/api/v2/pokemon-species/2/',
            ],
        ], JSON_THROW_ON_ERROR);

        $speciesResponse = json_encode([
            'growth_rate' => [
                'url' => 'https://pokeapi.co/api/v2/growth-rate/3/',
            ],
        ], JSON_THROW_ON_ERROR);

        $callCount = 0;
        $httpGetter = static function (string $url) use (&$callCount, $pokemonResponse, $speciesResponse): string {
            ++$callCount;

            if ($callCount === 1) {
                return $pokemonResponse;
            }

            return $speciesResponse;
        };

        $provider = $this->createProviderWithCallable($httpGetter);
        $result = $provider->fetchPokemonData(new PokemonName('ivysaur'));

        self::assertInstanceOf(PokemonDataResult::class, $result);
        self::assertSame('ivysaur', $result->name->value);
        self::assertSame(142, $result->experience);
        self::assertSame('ivysaur', $result->species->value);
        self::assertSame(
            'https://pokeapi.co/api/v2/growth-rate/3/',
            $result->growthRateReference->value,
        );
    }

    /** @test */
    public function testThrowsOnMalformedJson(): void
    {
        $httpGetter = static fn(string $url): string => 'not json';

        $this->expectException(\JsonException::class);

        $provider = $this->createProviderWithCallable($httpGetter);
        $provider->fetchPokemonData(new PokemonName('ivysaur'));
    }

    /** @test */
    public function testThrowsOnMissingField(): void
    {
        $pokemonResponse = json_encode([
            'species' => [
                'name' => 'ivysaur',
                'url' => 'https://pokeapi.co/api/v2/pokemon-species/2/',
            ],
        ], JSON_THROW_ON_ERROR);

        $speciesResponse = json_encode([
            'growth_rate' => [
                'url' => 'https://pokeapi.co/api/v2/growth-rate/3/',
            ],
        ], JSON_THROW_ON_ERROR);

        $callCount = 0;
        $httpGetter = static function (string $url) use (&$callCount, $pokemonResponse, $speciesResponse): string {
            ++$callCount;

            if ($callCount === 1) {
                return $pokemonResponse;
            }

            return $speciesResponse;
        };

        $this->expectException(\PHPUnit\Framework\Error\Warning::class);

        $provider = $this->createProviderWithCallable($httpGetter);
        $provider->fetchPokemonData(new PokemonName('ivysaur'));
    }

    /** @test */
    public function testThrowsOnMissingSpeciesFieldInResponse(): void
    {
        $pokemonResponse = json_encode([
            'base_experience' => 142,
        ], JSON_THROW_ON_ERROR);

        $speciesResponse = json_encode([
            'growth_rate' => [
                'url' => 'https://pokeapi.co/api/v2/growth-rate/3/',
            ],
        ], JSON_THROW_ON_ERROR);

        $callCount = 0;
        $httpGetter = static function (string $url) use (&$callCount, $pokemonResponse, $speciesResponse): string {
            ++$callCount;

            if ($callCount === 1) {
                return $pokemonResponse;
            }

            return $speciesResponse;
        };

        $this->expectException(\PHPUnit\Framework\Error\Warning::class);

        $provider = $this->createProviderWithCallable($httpGetter);
        $provider->fetchPokemonData(new PokemonName('ivysaur'));
    }

    /** @test */
    public function testThrowsOnMissingGrowthRateFieldInSpeciesResponse(): void
    {
        $pokemonResponse = json_encode([
            'base_experience' => 142,
            'species' => [
                'name' => 'ivysaur',
                'url' => 'https://pokeapi.co/api/v2/pokemon-species/2/',
            ],
        ], JSON_THROW_ON_ERROR);

        $speciesResponse = json_encode([
            'name' => 'ivysaur',
        ], JSON_THROW_ON_ERROR);

        $callCount = 0;
        $httpGetter = static function (string $url) use (&$callCount, $pokemonResponse, $speciesResponse): string {
            ++$callCount;

            if ($callCount === 1) {
                return $pokemonResponse;
            }

            return $speciesResponse;
        };

        $this->expectException(\PHPUnit\Framework\Error\Warning::class);

        $provider = $this->createProviderWithCallable($httpGetter);
        $provider->fetchPokemonData(new PokemonName('ivysaur'));
    }
}