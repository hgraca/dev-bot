/*
 * src/agentic/forensics/langs/java/Metrics.java
 *
 * Java unit collector for the forensics tool. Uses only the JDK's compiler tree
 * API (com.sun.source, javax.tools) — no external dependencies — to emit code
 * units (classes + methods + constructors) with cyclomatic complexity and line
 * spans.
 *
 * Usage:  java Metrics.java <projectRoot> <File> [<File> ...]
 * Output: {"ok": true, "units": [...], "errors": []}
 */

import com.sun.source.tree.BinaryTree;
import com.sun.source.tree.BlockTree;
import com.sun.source.tree.CaseTree;
import com.sun.source.tree.CatchTree;
import com.sun.source.tree.ClassTree;
import com.sun.source.tree.CompilationUnitTree;
import com.sun.source.tree.ConditionalExpressionTree;
import com.sun.source.tree.DoWhileLoopTree;
import com.sun.source.tree.ForLoopTree;
import com.sun.source.tree.IfTree;
import com.sun.source.tree.LambdaExpressionTree;
import com.sun.source.tree.MethodTree;
import com.sun.source.tree.Tree;
import com.sun.source.tree.VariableTree;
import com.sun.source.tree.WhileLoopTree;
import com.sun.source.util.JavacTask;
import com.sun.source.util.SourcePositions;
import com.sun.source.util.TreeScanner;
import com.sun.source.util.Trees;

import javax.tools.JavaCompiler;
import javax.tools.JavaFileObject;
import javax.tools.StandardJavaFileManager;
import javax.tools.ToolProvider;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public final class Metrics {

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("ERROR: usage: Metrics.java <projectRoot> <File> [<File> ...]");
            System.exit(2);
        }
        Path project = Paths.get(args[0]);
        List<String> files = new ArrayList<>(Arrays.asList(args).subList(1, args.length));
        if (files.isEmpty()) {
            System.out.print("{\"ok\":true,\"units\":[],\"errors\":[]}");
            return;
        }

        JavaCompiler compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null) {
            System.err.println("ERROR: no system Java compiler on the classpath (need a JDK)");
            System.exit(1);
        }

        StandardJavaFileManager fileManager = compiler.getStandardFileManager(null, Locale.ROOT, StandardCharsets.UTF_8);
        Iterable<? extends JavaFileObject> objects = fileManager.getJavaFileObjectsFromStrings(files);
        JavacTask task = (JavacTask) compiler.getTask(
                new StringWriter(), fileManager, null,
                Arrays.asList("-proc:none", "-nowarn", "-encoding", "UTF-8"), null, objects);

        List<String> units = new ArrayList<>();
        for (CompilationUnitTree unit : task.parse()) {
            SourcePositions positions = Trees.instance(task).getSourcePositions();
            new UnitScanner(unit, positions, project, units).scan(unit, null);
        }

        System.out.print("{\"ok\":true,\"units\":[" + String.join(",", units) + "],\"errors\":[]}");
    }

    private static String jsonString(String value) {
        StringBuilder out = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
            }
        }
        return out.append("\"").toString();
    }

    /** A method's name with its parameter types, so overloads do not collide. */
    private static String signature(MethodTree method) {
        StringBuilder builder = new StringBuilder();
        builder.append("<init>".equals(method.getName().toString()) ? "constructor" : method.getName().toString());
        builder.append("(");
        List<? extends VariableTree> parameters = method.getParameters();
        for (int i = 0; i < parameters.size(); i++) {
            if (i > 0) {
                builder.append(",");
            }
            builder.append(parameters.get(i).getType().toString());
        }
        return builder.append(")").toString();
    }

    private static final class UnitScanner extends TreeScanner<Void, Void> {
        private final CompilationUnitTree unit;
        private final SourcePositions positions;
        private final Path project;
        private final List<String> units;

        UnitScanner(CompilationUnitTree unit, SourcePositions positions, Path project, List<String> units) {
            this.unit = unit;
            this.positions = positions;
            this.project = project;
            this.units = units;
        }

        @Override
        public Void visitClass(ClassTree node, Void unused) {
            String className = node.getSimpleName().toString();
            if (!className.isEmpty()) {
                long wmc = 0;
                for (Tree member : node.getMembers()) {
                    if (member instanceof MethodTree) {
                        MethodTree method = (MethodTree) member;
                        int complexity = complexityOf(method);
                        wmc += complexity;
                        units.add(entry(className + "::" + signature(method), "method", method, complexity, className));
                    } else if (member instanceof BlockTree) {
                        // Instance / static initializer block: counted in WMC, not a unit.
                        wmc += complexityOf(member);
                    }
                }
                units.add(entry(className, "class", node, (int) wmc, ""));
            }
            return super.visitClass(node, unused);
        }

        private int complexityOf(Tree tree) {
            ComplexityCounter counter = new ComplexityCounter();
            counter.scanRoot(tree);
            return counter.complexity;
        }

        private String entry(String name, String kind, Tree node, int complexity, String parent) {
            long start = positions.getStartPosition(unit, node);
            long end = positions.getEndPosition(unit, node);
            long startLine = unit.getLineMap().getLineNumber(start);
            long endLine = end > 0 ? unit.getLineMap().getLineNumber(end) : startLine;
            String path = project.relativize(Paths.get(unit.getSourceFile().toUri())).toString();
            return "{"
                    + "\"path\":" + jsonString(path)
                    + ",\"name\":" + jsonString(name)
                    + ",\"kind\":" + jsonString(kind)
                    + ",\"start_line\":" + startLine
                    + ",\"end_line\":" + endLine
                    + ",\"complexity\":" + complexity
                    + ",\"loc\":" + (endLine - startLine + 1)
                    + ",\"parent\":" + jsonString(parent)
                    + "}";
        }
    }

    private static final class ComplexityCounter extends TreeScanner<Void, Void> {
        int complexity = 1;
        private Tree root;

        void scanRoot(Tree tree) {
            this.root = tree;
            scan(tree, null);
        }

        @Override public Void visitIf(IfTree node, Void unused) { complexity++; return super.visitIf(node, unused); }
        @Override public Void visitForLoop(ForLoopTree node, Void unused) { complexity++; return super.visitForLoop(node, unused); }
        @Override public Void visitWhileLoop(WhileLoopTree node, Void unused) { complexity++; return super.visitWhileLoop(node, unused); }
        @Override public Void visitDoWhileLoop(DoWhileLoopTree node, Void unused) { complexity++; return super.visitDoWhileLoop(node, unused); }
        @Override public Void visitCase(CaseTree node, Void unused) { complexity++; return super.visitCase(node, unused); }
        @Override public Void visitCatch(CatchTree node, Void unused) { complexity++; return super.visitCatch(node, unused); }
        @Override public Void visitConditionalExpression(ConditionalExpressionTree node, Void unused) { complexity++; return super.visitConditionalExpression(node, unused); }

        @Override
        public Void visitBinary(BinaryTree node, Void unused) {
            Tree.Kind kind = node.getKind();
            if (kind == Tree.Kind.CONDITIONAL_AND || kind == Tree.Kind.CONDITIONAL_OR) {
                complexity++;
            }
            return super.visitBinary(node, unused);
        }

        // Nested scopes are their own units — do not inflate the enclosing one.
        @Override public Void visitClass(ClassTree node, Void unused) { return node == root ? super.visitClass(node, unused) : null; }
        @Override public Void visitMethod(MethodTree node, Void unused) { return node == root ? super.visitMethod(node, unused) : null; }
        @Override public Void visitLambdaExpression(LambdaExpressionTree node, Void unused) { return null; }
    }
}
