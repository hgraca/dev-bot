<?php

declare(strict_types=1);

namespace Demo;

final class UsesWidget
{
    public function run(): string
    {
        $widget = Widget::make();

        return $widget->label;
    }
}
