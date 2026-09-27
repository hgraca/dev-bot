<?php

namespace Fixture;

class Calculator
{
    public function add(int $a, int $b): int
    {
        return $a + $b;
    }

    public function classify(int $n): string
    {
        if ($n < 0) {
            return 'negative';
        }
        if ($n === 0) {
            return 'zero';
        }
        return 'positive';
    }
}
