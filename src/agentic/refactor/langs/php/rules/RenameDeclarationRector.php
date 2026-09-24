<?php

declare(strict_types=1);

namespace Devbot\Refactor;

use PhpParser\Node;
use PhpParser\Node\Const_ as ConstNode;
use PhpParser\Node\Identifier;
use PhpParser\Node\Stmt\Class_;
use PhpParser\Node\Stmt\Const_ as ConstStmt;
use PhpParser\Node\Stmt\Function_;
use Rector\Contract\Rector\ConfigurableRectorInterface;
use Rector\Rector\AbstractRector;
use Symplify\RuleDocGenerator\ValueObject\RuleDefinition;

/**
 * Renames a *declaration* — the half Rector's own renaming rules omit.
 *
 * Rector's Renaming rules are usages-only (`FuncCall`, `ConstFetch`,
 * `StaticCall`, `Name`); apart from `RenameMethodRector` none rewrites the
 * declaration, so pairing one of them with this rule is what makes a rename
 * complete rather than a half-rename that references a name nothing defines.
 *
 * Configured with:
 *   kind — "function" | "constant" | "class"
 *   from — the declaration's SHORT name
 *   to   — the new SHORT name
 *
 * Class declarations are renamed here; moving the file to match (PSR-4) is the
 * caller's job, since Rector does not move files.
 */
final class RenameDeclarationRector extends AbstractRector implements ConfigurableRectorInterface
{
    private string $kind = '';

    private string $from = '';

    private string $to = '';

    public function getRuleDefinition(): RuleDefinition
    {
        return new RuleDefinition('Rename a declaration (function, constant, class)', []);
    }

    /**
     * @return array<class-string<Node>>
     */
    public function getNodeTypes(): array
    {
        return [Function_::class, ConstStmt::class, Class_::class];
    }

    public function refactor(Node $node): ?Node
    {
        if ($node instanceof Function_ && $this->kind === 'function') {
            return $this->rename($node, $node->name);
        }

        if ($node instanceof Class_ && $this->kind === 'class') {
            return $this->rename($node, $node->name);
        }

        if ($node instanceof ConstStmt && $this->kind === 'constant') {
            foreach ($node->consts as $const) {
                if ($const instanceof ConstNode && $const->name->toString() === $this->from) {
                    $const->name = new Identifier($this->to);

                    return $node;
                }
            }
        }

        return null;
    }

    private function rename(Function_|Class_ $node, ?Identifier $name): ?Node
    {
        if ($name === null) {
            return null;
        }

        // `from` may be the short name or the fully-qualified one; the qualified
        // form is what keeps a common short name from matching another namespace.
        $candidate = $name->toString();
        $namespaced = $node->namespacedName !== null ? $node->namespacedName->toString() : null;
        if ($this->from !== $candidate && $this->from !== $namespaced) {
            return null;
        }

        $node->name = new Identifier($this->to);

        return $node;
    }

    /**
     * @param mixed[] $configuration
     */
    public function configure(array $configuration): void
    {
        $this->kind = (string) ($configuration['kind'] ?? '');
        $this->from = (string) ($configuration['from'] ?? '');
        // The declaration keeps the short name even when `to` is qualified.
        $this->to = self::shortName((string) ($configuration['to'] ?? ''));
    }

    private static function shortName(string $name): string
    {
        $position = strrpos($name, '\\');

        return $position === false ? $name : substr($name, $position + 1);
    }
}
