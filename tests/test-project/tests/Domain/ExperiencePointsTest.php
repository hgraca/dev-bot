<?php

declare(strict_types=1);

namespace Gete\PokeParser\Test\Domain;

use Gete\PokeParser\Domain\ExperiencePoints;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Gete\PokeParser\Domain\ExperiencePoints
 */
final class ExperiencePointsTest extends TestCase
{
    /** @test */
    public function it_stores_the_experience_value(): void
    {
        $exp = new ExperiencePoints(100);

        self::assertSame(100, $exp->value);
    }

    /** @test */
    public function it_accepts_zero_experience(): void
    {
        $exp = new ExperiencePoints(0);

        self::assertSame(0, $exp->value);
    }

    /** @test */
    public function it_throws_an_exception_on_negative_value(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Experience points cannot be negative');

        new ExperiencePoints(-1);
    }

    /** @test */
    public function it_throws_an_exception_on_a_large_negative_value(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        new ExperiencePoints(-999999);
    }
}
