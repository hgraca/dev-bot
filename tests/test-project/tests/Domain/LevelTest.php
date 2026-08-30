<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\Level;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\Level
 */
final class LevelTest extends TestCase
{
    /** @test */
    public function it_stores_the_level_value(): void
    {
        $level = new Level(42);

        self::assertSame(42, $level->value);
    }

    /** @test */
    public function it_accepts_the_minimum_level(): void
    {
        $level = new Level(1);

        self::assertSame(1, $level->value);
    }

    /** @test */
    public function it_accepts_the_maximum_level(): void
    {
        $level = new Level(100);

        self::assertSame(100, $level->value);
    }

    /** @test */
    public function it_throws_an_exception_when_level_is_below_minimum(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Level must be between 1 and 100');

        new Level(0);
    }

    /** @test */
    public function it_throws_an_exception_when_level_is_above_maximum(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Level must be between 1 and 100');

        new Level(101);
    }

    /** @test */
    public function it_throws_an_exception_on_negative_level(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        new Level(-5);
    }
}
