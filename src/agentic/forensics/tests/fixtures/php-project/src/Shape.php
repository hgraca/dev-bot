<?php

namespace Fixture;

trait Greets
{
    public function greet(string $name): string
    {
        if ($name === '') {
            return 'hi';
        }

        return 'hello ' . $name;
    }
}

enum Level: int
{
    case Low = 1;
    case High = 2;

    public function label(): string
    {
        return $this->value > 1 ? 'high' : 'low';
    }
}
