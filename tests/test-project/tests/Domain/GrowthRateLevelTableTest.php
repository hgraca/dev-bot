<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\GrowthRateLevel;
use Gete\PokeParser\Domain\GrowthRateLevelTable;
use Gete\PokeParser\Domain\Level;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\GrowthRateLevelTable
 */
final class GrowthRateLevelTableTest extends TestCase
{
    /**
     * Simulates a medium growth rate table (PokeAPI-style).
     *
     * level   1: required_experience = 0
     * level   2: required_experience = 583
     * level   3: required_experience = 1250
     * level  10: required_experience = 13000
     * level  25: required_experience = 80000
     * level  50: required_experience = 320000
     * level 100: required_experience = 1000000
     */
    private function createMediumGrowthTable(): GrowthRateLevelTable
    {
        return new GrowthRateLevelTable(
            new GrowthRateLevel(0, new Level(1)),
            new GrowthRateLevel(583, new Level(2)),
            new GrowthRateLevel(1250, new Level(3)),
            new GrowthRateLevel(13000, new Level(10)),
            new GrowthRateLevel(80000, new Level(25)),
            new GrowthRateLevel(320000, new Level(50)),
            new GrowthRateLevel(1000000, new Level(100)),
        );
    }

    // ── Exact match ───────────────────────────────────────────────

    /** @test */
    public function it_returns_level_1_when_experience_exactly_matches_first_threshold(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(0);

        self::assertNotNull($level);
        self::assertSame(1, $level->value);
    }

    /** @test */
    public function it_returns_the_correct_level_on_exact_experience_match(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(583);

        self::assertNotNull($level);
        self::assertSame(2, $level->value);
    }

    /** @test */
    public function it_returns_max_level_when_experience_exactly_matches_max_threshold(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(1_000_000);

        self::assertNotNull($level);
        self::assertSame(100, $level->value);
    }

    // ── Between thresholds ────────────────────────────────────────

    /** @test */
    public function it_returns_the_lower_level_when_experience_is_between_thresholds(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(300);

        self::assertNotNull($level);
        self::assertSame(1, $level->value);
    }

    /** @test */
    public function it_returns_level_2_when_experience_is_between_583_and_1250(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(900);

        self::assertNotNull($level);
        self::assertSame(2, $level->value);
    }

    /** @test */
    public function it_returns_level_25_when_experience_is_between_80000_and_320000(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(200_000);

        self::assertNotNull($level);
        self::assertSame(25, $level->value);
    }

    // ── Above max threshold (bug fix) ─────────────────────────────

    /** @test */
    public function it_returns_highest_level_when_experience_exceeds_max_threshold(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(2_000_000);

        self::assertNotNull($level);
        self::assertSame(100, $level->value);
    }

    /** @test */
    public function it_returns_highest_level_when_experience_is_well_above_max(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(99_999_999);

        self::assertNotNull($level);
        self::assertSame(100, $level->value);
    }

    // ── Empty table ───────────────────────────────────────────────

    /** @test */
    public function it_returns_null_when_level_table_is_empty(): void
    {
        $table = new GrowthRateLevelTable();

        $level = $table->levelFor(0);

        self::assertNull($level);
    }

    /** @test */
    public function it_returns_null_when_level_table_is_empty_even_with_large_experience(): void
    {
        $table = new GrowthRateLevelTable();

        $level = $table->levelFor(999_999);

        self::assertNull($level);
    }

    // ── Experience at 0 ───────────────────────────────────────────

    /** @test */
    public function it_returns_first_level_when_experience_is_zero(): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor(0);

        self::assertNotNull($level);
        self::assertSame(1, $level->value);
    }

    // ── Data-driven edge cases ────────────────────────────────────

    /**
     * @return array<string, array{int, int}>
     */
    public static function provideExperienceToLevel(): array
    {
        return [
            'experience 0'             => [0, 1],
            'experience 300'           => [300, 1],
            'experience 582'           => [582, 1],
            'experience 583'           => [583, 2],
            'experience 1000'          => [1000, 2],
            'experience 1249'          => [1249, 2],
            'experience 1250'          => [1250, 3],
            'experience 5000'          => [5000, 3],
            'experience 12999'         => [12999, 3],
            'experience 13000'         => [13000, 10],
            'experience 50000'         => [50000, 10],
            'experience 79999'         => [79999, 10],
            'experience 80000'         => [80000, 25],
            'experience 150000'        => [150000, 25],
            'experience 319999'        => [319999, 25],
            'experience 320000'        => [320000, 50],
            'experience 999999'        => [999999, 50],
            'experience 1000000'       => [1000000, 100],
            'experience above max'     => [2000000, 100],
        ];
    }

    /**
     * @dataProvider provideExperienceToLevel
     * @test
     */
    public function it_finds_the_correct_level_for_various_experience_values(int $experience, int $expectedLevel): void
    {
        $table = $this->createMediumGrowthTable();

        $level = $table->levelFor($experience);

        self::assertNotNull($level);
        self::assertSame($expectedLevel, $level->value);
    }

    // ── Atypical table: non-sequential levels ─────────────────────

    /** @test */
    public function it_works_with_non_sequential_level_jumps(): void
    {
        $table = new GrowthRateLevelTable(
            new GrowthRateLevel(0, new Level(5)),
            new GrowthRateLevel(1000, new Level(15)),
            new GrowthRateLevel(5000, new Level(30)),
        );

        self::assertSame(5, $table->levelFor(0)?->value);
        self::assertSame(5, $table->levelFor(500)?->value);
        self::assertSame(15, $table->levelFor(1000)?->value);
        self::assertSame(15, $table->levelFor(3000)?->value);
        self::assertSame(30, $table->levelFor(5000)?->value);
        self::assertSame(30, $table->levelFor(10_000)?->value);
    }

    // ── Single level table ────────────────────────────────────────

    /** @test */
    public function it_returns_the_only_level_when_table_has_one_entry(): void
    {
        $table = new GrowthRateLevelTable(
            new GrowthRateLevel(0, new Level(1)),
        );

        self::assertSame(1, $table->levelFor(0)?->value);
        self::assertSame(1, $table->levelFor(1000)?->value);
        self::assertSame(1, $table->levelFor(1_000_000)?->value);
    }

    // ── stores levels array ───────────────────────────────────────

    /** @test */
    public function it_stores_the_levels_array(): void
    {
        $table = $this->createMediumGrowthTable();

        $levels = $table->levels;

        self::assertCount(7, $levels);
        self::assertContainsOnlyInstancesOf(GrowthRateLevel::class, $levels);
    }
}
