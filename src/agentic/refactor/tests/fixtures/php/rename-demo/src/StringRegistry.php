<?php

declare(strict_types=1);

namespace Demo;

final class StringRegistry
{
    /**
     * A reference held in a string: no renaming rule here can see it, so the tool
     * must report it rather than leave it behind silently.
     *
     * @var array<string, class-string>
     */
    private const MAP = [
        'primary' => 'Widget',
    ];

    public function resolve(string $key): string
    {
        return self::MAP[$key] ?? '';
    }
}
