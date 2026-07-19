import Foundation

/// The Python script `PythonIndexer` feeds to `python3` on stdin (via
/// `PythonIndexer.runAST`) to do the actual parsing. Deliberately small and
/// dependency-free (stdlib `ast` + `json` only) so it runs on any `python3`
/// without a `pip install` step.
///
/// Contract (stdin → stdout), matched by `PythonIndexer.Declaration` and
/// `PythonIndexer.Call`:
///
/// Input: raw Python source on stdin.
///
/// Success (exit 0), one JSON object on stdout:
/// ```json
/// {
///   "ok": true,
///   "declarations": [
///     { "kind": "func", "name": "add", "arity": 2, "path": ["add"] },
///     { "kind": "class", "name": "Greeter", "arity": 0, "path": ["Greeter"] },
///     { "kind": "func", "name": "hello", "arity": 0, "path": ["Greeter", "hello"] }
///   ],
///   "calls": [
///     { "decl_path": ["Greeter", "hello"], "name": "add", "arity": 2 }
///   ]
/// }
/// ```
/// - `kind` is one of `"func"`, `"class"`, `"var"` — the same Channel-0
///   vocabulary `SwiftIndexer` uses (a Python `def` is a `"func"` so a
///   same-shaped Swift `func` and Python `def` produce an identical
///   Channel-0 skeleton line).
/// - `arity` for a `func`: count of positional + keyword-only parameters,
///   **excluding a leading `self`/`cls`** when the function is defined
///   directly inside a class body. This is a deliberate choice (see
///   `PythonIndexer`'s doc comment) so a Python instance method's arity
///   matches what a caller supplies (`greeter.hello()` is 0 args), which is
///   also what a free Swift `func` with the same call shape would report.
///   `*args`/`**kwargs` and positional-only markers are not counted (no
///   variadic vocabulary on the Swift side to match against).
/// - `path` is enclosing class/function names (by lexical nesting) + this
///   declaration's own name — module is NOT included; `PythonIndexer`
///   prepends it, exactly like `SwiftIndexer` prepends `module`.
/// - `calls` is a flat list of every `ast.Call` found inside a declaration's
///   body (excluding nested declarations). `decl_path` matches the declaration's
///   `path`. `name` is the called symbol (`node.id` for `ast.Name`, `node.attr`
///   for `ast.Attribute`). `arity` is `len(node.args)` (positional arguments only).
/// - Top-level (module-scope) simple assignments (`NAME = ...`) are emitted
///   as `kind: "var"`, mirroring Swift's top-level `let`/`var`. Only `Name`
///   targets are considered (no tuple/attribute/subscript unpacking) — a
///   narrow v0 signal, not a full dataflow analysis. Assignments inside a
///   function body are NOT recorded (locals aren't structural declarations);
///   assignments directly inside a class body (class-level attributes) ARE
///   recorded, nested under the class's path.
///
/// Failure — a genuine Python syntax error (exit code 1), one JSON object on
/// stdout:
/// ```json
/// { "ok": false, "error": "SyntaxError", "message": "...", "lineno": 3, "offset": 5 }
/// ```
/// `lineno`/`offset` may be `null` if Python's `SyntaxError` didn't carry
/// them. `PythonIndexer` surfaces this as node status `.red` (see
/// `PythonIndexer.indexWithStatus`) rather than crashing or silently
/// producing an empty tree.
enum PythonASTScript {
    static let source = """
    import ast
    import json
    import sys


    def param_names(args):
        names = []
        names += [a.arg for a in getattr(args, "posonlyargs", [])]
        names += [a.arg for a in args.args]
        names += [a.arg for a in args.kwonlyargs]
        return names


    def walk_body(body, in_class, scope, out):
        \"\"\"Recursively find func/class/var declarations in `body`, tracking
        lexical `scope` (list of enclosing class/function names) and whether
        we are directly inside a class body (`in_class`) so method arity can
        drop a leading self/cls. Descends into if/for/while/with/try blocks
        without treating them as scopes of their own, so declarations nested
        in control flow are still found at their enclosing function/class's
        scope.\"\"\"
        for stmt in body:
            if isinstance(stmt, ast.ClassDef):
                out.append({
                    "kind": "class",
                    "name": stmt.name,
                    "arity": 0,
                    "path": scope + [stmt.name],
                    "body": stmt.body,
                })
                walk_body(stmt.body, True, scope + [stmt.name], out)
            elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
                names = param_names(stmt.args)
                if in_class and names and names[0] in ("self", "cls"):
                    names = names[1:]
                out.append({
                    "kind": "func",
                    "name": stmt.name,
                    "arity": len(names),
                    "path": scope + [stmt.name],
                    "body": stmt.body,
                })
                walk_body(stmt.body, False, scope + [stmt.name], out)
            elif isinstance(stmt, ast.Assign):
                for target in stmt.targets:
                    if isinstance(target, ast.Name):
                        out.append({
                            "kind": "var",
                            "name": target.id,
                            "arity": 0,
                            "path": scope + [target.id],
                            "body": [],
                        })
            elif isinstance(stmt, (ast.If, ast.For, ast.AsyncFor, ast.While, ast.With, ast.AsyncWith, ast.Try)):
                nested = list(getattr(stmt, "body", []))
                nested += list(getattr(stmt, "orelse", []))
                nested += list(getattr(stmt, "finalbody", []))
                for handler in getattr(stmt, "handlers", []):
                    nested += list(handler.body)
                walk_body(nested, in_class, scope, out)


    def extract_calls(node, out):
        \"\"\"Recursively collect ast.Call nodes under `node`, skipping nested
        func/class definitions so calls inside nested declarations are not
        attributed to an outer scope.\"\"\"
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            return
        for child in ast.iter_child_nodes(node):
            if isinstance(child, ast.Call):
                name = None
                if isinstance(child.func, ast.Name):
                    name = child.func.id
                elif isinstance(child.func, ast.Attribute):
                    name = child.func.attr
                if name is not None:
                    out.append({"name": name, "arity": len(child.args)})
            extract_calls(child, out)


    def main():
        source = sys.stdin.read()
        try:
            tree = ast.parse(source)
        except SyntaxError as e:
            print(json.dumps({
                "ok": False,
                "error": "SyntaxError",
                "message": str(e.msg) if e.msg else str(e),
                "lineno": e.lineno,
                "offset": e.offset,
            }))
            sys.exit(1)

        declarations = []
        walk_body(tree.body, False, [], declarations)

        calls = []
        for decl in declarations:
            decl_body = decl.pop("body", [])
            decl_calls = []
            for stmt in decl_body:
                extract_calls(stmt, decl_calls)
            for c in decl_calls:
                calls.append({
                    "decl_path": decl["path"],
                    "name": c["name"],
                    "arity": c["arity"],
                })

        print(json.dumps({"ok": True, "declarations": declarations, "calls": calls}))


    if __name__ == "__main__":
        main()
    """
}
