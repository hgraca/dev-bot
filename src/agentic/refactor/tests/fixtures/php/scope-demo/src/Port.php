<?php

declare(strict_types=1);

namespace Demo;

interface Port
{
    public function emit(string $message): void;
}
