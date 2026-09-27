<?php

/**
 * src/agentic/forensics/langs/php/metrics.php
 *
 * PDepend-backed unit collector for the forensics PHP plugin. Reads a JSON
 * request on stdin, walks the given files with PDepend's analyzers, and prints
 * code units (class + method) with static complexity as canonical JSON.
 *
 * Request:  {"project": "/app", "autoload": "/…/vendor/autoload.php", "files": ["src/Foo.php", …]}
 * Response: {"ok": true, "units": [{path, name, kind, start_line, end_line, complexity, loc, parent}], "errors": []}
 *
 * The project is mounted read-only; this script writes nothing.
 */

declare(strict_types=1);

// PDepend 2.16 predates PHP 8.4 and emits deprecation notices while its classes
// load. Silence them so stdout stays pure JSON for the caller.
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

use PDepend\Application;
use PDepend\Metrics\Analyzer;
use PDepend\Metrics\AnalyzerNodeAware;
use PDepend\Report\CodeAwareGenerator;
use PDepend\Source\AST\ASTArtifactList;
use PDepend\Source\AST\ASTClass;
use PDepend\Source\AST\ASTEnum;
use PDepend\Source\AST\ASTInterface;
use PDepend\Source\AST\ASTTrait;
use PDepend\Source\AST\AbstractASTClassOrInterface;
use PDepend\Source\ASTVisitor\AbstractASTVisitor;

// The request and the autoloader must be resolved before the collector class is
// declared: it extends a PDepend type, so the autoloader has to be registered by
// the time the declaration executes.
$request = json_decode((string) stream_get_contents(STDIN), true);
if (!is_array($request)) {
    fwrite(STDERR, "ERROR: invalid JSON request\n");
    exit(2);
}

$project = rtrim((string) ($request['project'] ?? ''), '/');
$autoload = (string) ($request['autoload'] ?? '');
$files = is_array($request['files'] ?? null) ? $request['files'] : [];

if ($autoload === '' || !is_file($autoload)) {
    fwrite(STDERR, "ERROR: autoload not found: {$autoload}\n");
    exit(1);
}

require $autoload;

final class UnitCollector extends AbstractASTVisitor implements CodeAwareGenerator
{
    /** @var Analyzer[] */
    private $analyzers = [];

    /** @var ASTArtifactList */
    private $artifacts;

    /** @var string */
    private $project;

    /** @var array<string,array> keyed by path|kind|name to fold duplicate traversals */
    private $units = [];

    public function __construct(string $project)
    {
        $this->project = rtrim($project, '/');
    }

    public function setArtifacts(ASTArtifactList $artifacts)
    {
        $this->artifacts = $artifacts;
    }

    public function log(Analyzer $analyzer)
    {
        $this->analyzers[] = $analyzer;

        return true;
    }

    public function getAcceptedAnalyzers()
    {
        return [
            'pdepend.analyzer.cyclomatic_complexity',
            'pdepend.analyzer.node_loc',
            'pdepend.analyzer.npath_complexity',
            'pdepend.analyzer.inheritance',
            'pdepend.analyzer.node_count',
            'pdepend.analyzer.hierarchy',
            'pdepend.analyzer.crap_index',
            'pdepend.analyzer.code_rank',
            'pdepend.analyzer.coupling',
            'pdepend.analyzer.class_level',
            'pdepend.analyzer.cohesion',
        ];
    }

    public function close()
    {
        foreach ($this->artifacts as $namespace) {
            $namespace->accept($this);
        }
        echo json_encode(
            ['ok' => true, 'units' => array_values($this->units), 'errors' => []],
            JSON_UNESCAPED_SLASHES
        );
    }

    public function visitClass(ASTClass $node)
    {
        $this->collect($node, 'class');
        parent::visitClass($node);
    }

    public function visitInterface(ASTInterface $node)
    {
        $this->collect($node, 'interface');
        parent::visitInterface($node);
    }

    public function visitTrait(ASTTrait $node)
    {
        $this->collect($node, 'trait');
        parent::visitTrait($node);
    }

    public function visitEnum(ASTEnum $node)
    {
        $this->collect($node, 'enum');
        parent::visitEnum($node);
    }

    private function collect(AbstractASTClassOrInterface $node, string $kind)
    {
        if (!$node->isUserDefined()) {
            return;
        }

        $relative = $this->relative($node->getCompilationUnit()->getFileName());
        $classMetrics = $this->metrics($node);
        $this->addUnit($relative, $node->getName(), $kind, $node, $classMetrics['wmc'] ?? null, $classMetrics['loc'] ?? null, '');

        foreach ($node->getMethods() as $method) {
            $methodMetrics = $this->metrics($method);
            $complexity = $methodMetrics['ccn2'] ?? $methodMetrics['ccn'] ?? null;
            $this->addUnit(
                $relative,
                $node->getName() . '::' . $method->getName(),
                'method',
                $method,
                $complexity,
                $methodMetrics['loc'] ?? null,
                $node->getName()
            );
        }
    }

    private function metrics($node): array
    {
        $merged = [];
        foreach ($this->analyzers as $analyzer) {
            if (!$analyzer instanceof AnalyzerNodeAware) {
                continue;
            }
            $metrics = $analyzer->getNodeMetrics($node);
            if (is_array($metrics)) {
                $merged = array_merge($merged, $metrics);
            }
        }

        return $merged;
    }

    private function addUnit(string $path, string $name, string $kind, $node, $complexity, $loc, string $parent): void
    {
        $this->units[$path . '|' . $kind . '|' . $name] = [
            'path' => $path,
            'name' => $name,
            'kind' => $kind,
            'start_line' => $node->getStartLine(),
            'end_line' => $node->getEndLine(),
            'complexity' => $complexity === null ? null : (int) $complexity,
            'loc' => $loc === null ? null : (int) $loc,
            'parent' => $parent,
        ];
    }

    private function relative(string $file): string
    {
        if ($this->project !== '' && strpos($file, $this->project . '/') === 0) {
            return substr($file, strlen($this->project) + 1);
        }

        return ltrim($file, '/');
    }
}

$engine = (new Application())->getEngine();
foreach ($files as $relative) {
    $absolute = $project . '/' . ltrim((string) $relative, '/');
    if (is_file($absolute)) {
        $engine->addFile($absolute);
    }
}
$engine->addReportGenerator(new UnitCollector($project));
$engine->analyze();
