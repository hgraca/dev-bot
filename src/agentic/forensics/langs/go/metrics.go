// src/agentic/forensics/langs/go/metrics.go
//
// Go unit collector for the forensics tool. Uses only the standard library
// (go/parser, go/ast, go/token) to emit code units — functions and methods —
// with cyclomatic complexity and line spans.
//
// Usage:  go run metrics.go <projectRoot> <File> [<File> ...]
// Output: {"ok": true, "units": [...], "errors": []}
package main

import (
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
)

type unit struct {
	Path       string `json:"path"`
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	StartLine  int    `json:"start_line"`
	EndLine    int    `json:"end_line"`
	Complexity int    `json:"complexity"`
	Loc        int    `json:"loc"`
	Parent     string `json:"parent"`
}

func complexity(node ast.Node) int {
	score := 1
	ast.Inspect(node, func(n ast.Node) bool {
		switch t := n.(type) {
		case *ast.IfStmt, *ast.ForStmt, *ast.RangeStmt, *ast.CaseClause, *ast.CommClause:
			score++
		case *ast.BinaryExpr:
			if t.Op == token.LAND || t.Op == token.LOR {
				score++
			}
		}
		return true
	})
	return score
}

func receiverName(expr ast.Expr) string {
	switch t := expr.(type) {
	case *ast.Ident:
		return t.Name
	case *ast.StarExpr:
		return receiverName(t.X)
	case *ast.IndexExpr:
		return receiverName(t.X)
	}
	return ""
}

func main() {
	args := os.Args[1:]
	if len(args) < 1 {
		os.Stderr.WriteString("ERROR: usage: metrics.go <projectRoot> <File> [...]\n")
		os.Exit(2)
	}
	project := args[0]
	files := args[1:]

	fileSet := token.NewFileSet()
	units := []unit{}
	for _, file := range files {
		parsed, err := parser.ParseFile(fileSet, file, nil, 0)
		if err != nil {
			continue
		}
		rel, err := filepath.Rel(project, file)
		if err != nil {
			rel = file
		}
		for _, decl := range parsed.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok {
				continue
			}
			start := fileSet.Position(fn.Pos()).Line
			end := fileSet.Position(fn.End()).Line
			name := fn.Name.Name
			kind := "function"
			parent := ""
			if fn.Recv != nil && len(fn.Recv.List) > 0 {
				parent = receiverName(fn.Recv.List[0].Type)
				kind = "method"
				name = parent + "::" + fn.Name.Name
			}
			units = append(units, unit{
				Path:       rel,
				Name:       name,
				Kind:       kind,
				StartLine:  start,
				EndLine:    end,
				Complexity: complexity(fn),
				Loc:        end - start + 1,
				Parent:     parent,
			})
		}
	}

	out, _ := json.Marshal(map[string]interface{}{"ok": true, "units": units, "errors": []string{}})
	os.Stdout.Write(out)
}
