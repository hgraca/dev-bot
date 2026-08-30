<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Application;

use GetE\MessageBus\Adapter\Dummy\HandlerResolver;
use GetE\MessageBus\Adapter\Dummy\QueryDispatcher;
use Gete\PokeParser\Application\FetchGrowthRateLevels;
use Gete\PokeParser\Application\FetchGrowthRateLevelsHandler;
use Gete\PokeParser\Application\FetchPokemonData;
use Gete\PokeParser\Application\FetchPokemonDataHandler;
use Gete\PokeParser\Application\GrowthRateLevelProvider;
use Gete\PokeParser\Application\PokemonDataProvider;
use Gete\PokeParser\Application\PokemonDataResult;
use Gete\PokeParser\Application\PokemonLevelService;
use Gete\PokeParser\Domain\GrowthRateLevel;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\GrowthRateReference;
use Gete\PokeParser\Domain\Level;
use Gete\PokeParser\Domain\PokemonName;
use Gete\PokeParser\Domain\Species;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Application\PokemonLevelService
 */
final class PokemonLevelServiceTest extends TestCase
{
    private function createMockPokemonDataProvider(): PokemonDataProvider
    {
        return new class implements PokemonDataProvider {
            public function fetchPokemonData(\Gete\PokeParser\Domain\PokemonName $name): PokemonDataResult
            {
                return new PokemonDataResult(
                    name: $name,
                    experience: 142,
                    species: new Species($name->value),
                    growthRateReference: new GrowthRateReference(
                        'https://pokeapi.co/api/v2/growth-rate/3/',
                    ),
                );
            }
        };
    }

    private function createMockGrowthRateLevelProvider(): GrowthRateLevelProvider
    {
        return new class implements GrowthRateLevelProvider {
            public function fetchGrowthRateLevels(GrowthRateReference $reference): GrowthRateLevelTable
            {
                return new GrowthRateLevelTable(
                    new GrowthRateLevel(0, new Level(1)),
                    new GrowthRateLevel(583, new Level(2)),
                    new GrowthRateLevel(1250, new Level(3)),
                    new GrowthRateLevel(2166, new Level(4)),
                    new GrowthRateLevel(3333, new Level(5)),
                    new GrowthRateLevel(5000, new Level(6)),
                );
            }
        };
    }

    private function createService(): PokemonLevelService
    {
        $pokemonDataProvider = $this->createMockPokemonDataProvider();
        $growthRateLevelProvider = $this->createMockGrowthRateLevelProvider();

        $handlerResolver = new class($pokemonDataProvider, $growthRateLevelProvider) implements HandlerResolver {
            public function __construct(
                private readonly PokemonDataProvider $pokemonDataProvider,
                private readonly GrowthRateLevelProvider $growthRateLevelProvider,
            ) {}

            public function resolve(string $handlerFqcn): object
            {
                return match ($handlerFqcn) {
                    FetchPokemonDataHandler::class => new FetchPokemonDataHandler(
                        $this->pokemonDataProvider,
                    ),
                    FetchGrowthRateLevelsHandler::class => new FetchGrowthRateLevelsHandler(
                        $this->growthRateLevelProvider,
                    ),
                    default => throw new \RuntimeException("Unknown handler: $handlerFqcn"),
                };
            }
        };

        $queryDispatcher = new QueryDispatcher($handlerResolver);

        return new PokemonLevelService($queryDispatcher);
    }

    /** @test */
    public function testCalculatesLevelForSinglePokemon(): void
    {
        $service = $this->createService();
        $results = $service->calculateLevels(new PokemonName('ivysaur'));

        self::assertCount(1, $results);
        self::assertSame('ivysaur', $results[0]->name->value);
        self::assertSame(142, $results[0]->experience->value);
        self::assertSame('ivysaur', $results[0]->species->value);
        self::assertSame(1, $results[0]->level->value);
    }

    /** @test */
    public function testCalculatesLevelsInInputOrder(): void
    {
        $service = $this->createService();
        $results = $service->calculateLevels(
            new PokemonName('ivysaur'),
            new PokemonName('bulbasaur'),
            new PokemonName('pikachu'),
        );

        self::assertCount(3, $results);
        self::assertSame('ivysaur', $results[0]->name->value);
        self::assertSame('bulbasaur', $results[1]->name->value);
        self::assertSame('pikachu', $results[2]->name->value);
    }

    /** @test */
    public function testReturnsEmptyArrayForNoInput(): void
    {
        $service = $this->createService();
        $results = $service->calculateLevels();

        self::assertSame([], $results);
    }

    /** @test */
    public function testUsesQueryDispatcherNotPortInterfaces(): void
    {
        $reflection = new \ReflectionClass(PokemonLevelService::class);
        $constructor = $reflection->getConstructor();

        self::assertNotNull($constructor);

        $params = $constructor->getParameters();
        self::assertCount(1, $params);

        $type = $params[0]->getType();
        self::assertNotNull($type);
        self::assertInstanceOf(\ReflectionNamedType::class, $type);
        self::assertFalse($type->isBuiltIn());

        $typeName = $type->getName();

        self::assertSame(QueryDispatcher::class, $typeName);
    }
}