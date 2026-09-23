<?php

declare(strict_types=1);

namespace Demo;

final class AnnotatedCase
{
    /**
     * @test
     */
    public function itWorks(): void
    {
    }

    /**
     * @test
     * @dataProvider provideThings
     */
    public function itWorksToo(): void
    {
    }
}
