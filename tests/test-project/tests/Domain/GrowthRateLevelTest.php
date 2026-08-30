<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\GrowthRateLevel;
use Gete\PokeParser\Domain\Level;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\GrowthRateLevel
 */
final class GrowthRateLevelTest extends TestCase
{
    private Level $level;
    private GrowthRateLevel $growthRateLevel;

    protected function setUp(): void
    {
        parent::setUp();

        $this->level = new Level(10);
        $this->growthRateLevel = new GrowthRateLevel(1000, $this->level);
    }

    /** @test */
    public function it_stores_the_required_experience(): void
    {
        self::assertSame(1000, $this->growthRateLevel->requiredExperience);
    }

    /** @test */
    public function it_stores_the_level(): void
    {
        self::assertSame($this->level, $this->growthRateLevel->level);
    }

    /** @test */
    public function it_accepts_zero_required_experience(): void
    {
        $level = new GrowthRateLevel(0, new Level(1));

        self::assertSame(0, $level->requiredExperience);
        self::assertSame(1, $level->level->value);
    }

    /** @test */
    public function it_accepts_a_high_required_experience(): void
    {
        $level = new GrowthRateLevel(1_000_000, new Level(100));

        self::assertSame(1_000_000, $level->requiredExperience);
        self::assertSame(100, $level->level->value);
    }
}
