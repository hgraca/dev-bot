<?php

declare(strict_types=1);

namespace Demo;

final class CleanupTarget
{
    protected string $promotable = 'x';

    private string $unusedProperty = 'y';

    private function unusedMethod(): string
    {
        return 'unused';
    }

    public function used(): string
    {
        return $this->promotable;
    }
}
