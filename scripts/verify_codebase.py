#!/usr/bin/env python3
"""
Fast (< 1s) Static & Structural Verification Suite for Nutsty.
Checks:
1. Python syntax compilation (`py_compile`) across `backend/*.py` and `launcher_win.py`.
2. AST Scope & Symbol Resolution across `backend/*.py` to catch any undefined globals (`NameError`).
3. QML/JS Module Contract Verification (`shell.qml` <-> `components/social_engine.js` & `components/playback_engine.js`).
"""

import ast
import builtins
import os
import py_compile
import re
import sys
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT_DIR / "backend"
COMPONENTS_DIR = ROOT_DIR / "components"

BUILTIN_NAMES = set(dir(builtins)) | {
    "__file__", "__name__", "__doc__", "__package__", "__loader__", "__spec__"
}


class ScopeAnalyzer(ast.NodeVisitor):
    """Collects module-level definitions and checks function bodies for unresolved global names."""

    def __init__(self, filename: str):
        self.filename = filename
        self.module_defs = set(BUILTIN_NAMES)
        self.unresolved = []

    def collect_top_level(self, tree: ast.Module):
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                self.module_defs.add(node.name)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    name = alias.asname or alias.name.split(".")[0]
                    self.module_defs.add(name)
            elif isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    if alias.name == "*":
                        continue
                    name = alias.asname or alias.name
                    self.module_defs.add(name)
            elif isinstance(node, ast.Assign):
                for target in node.targets:
                    self._add_target_names(target, self.module_defs)
            elif isinstance(node, ast.AnnAssign) and node.target:
                self._add_target_names(node.target, self.module_defs)

    def _add_target_names(self, target, name_set):
        if isinstance(target, ast.Name):
            name_set.add(target.id)
        elif isinstance(target, (ast.Tuple, ast.List)):
            for elt in target.elts:
                self._add_target_names(elt, name_set)

    def check_functions(self, tree: ast.Module):
        self._walk_scope(tree, set())

    def _collect_scope_locals(self, scope_node) -> set[str]:
        local_defs = set()
        if isinstance(scope_node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            for arg in (
                scope_node.args.posonlyargs
                + scope_node.args.args
                + scope_node.args.kwonlyargs
            ):
                local_defs.add(arg.arg)
            if scope_node.args.vararg:
                local_defs.add(scope_node.args.vararg.arg)
            if scope_node.args.kwarg:
                local_defs.add(scope_node.args.kwarg.arg)

        for sub in ast.walk(scope_node):
            if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                local_defs.add(sub.name)
            elif isinstance(sub, ast.Lambda):
                for arg in (
                    sub.args.posonlyargs + sub.args.args + sub.args.kwonlyargs
                ):
                    local_defs.add(arg.arg)
                if sub.args.vararg:
                    local_defs.add(sub.args.vararg.arg)
                if sub.args.kwarg:
                    local_defs.add(sub.args.kwarg.arg)
            elif isinstance(sub, (ast.Import, ast.ImportFrom)):
                for alias in sub.names:
                    local_defs.add(alias.asname or alias.name.split(".")[0])
            elif isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Store):
                local_defs.add(sub.id)
            elif isinstance(sub, ast.ExceptHandler) and sub.name:
                local_defs.add(sub.name)
            elif isinstance(sub, ast.comprehension):
                self._add_target_names(sub.target, local_defs)
            elif isinstance(sub, (ast.For, ast.AsyncFor)):
                self._add_target_names(sub.target, local_defs)
            elif isinstance(sub, (ast.With, ast.AsyncWith)):
                for item in sub.items:
                    if item.optional_vars:
                        self._add_target_names(item.optional_vars, local_defs)
            elif isinstance(sub, ast.NamedExpr):
                self._add_target_names(sub.target, local_defs)
        return local_defs

    def _iter_function_body_nodes(self, root_func):
        """Yields AST nodes inside root_func excluding nested FunctionDef/AsyncFunctionDef/ClassDef bodies."""
        stack = list(ast.iter_child_nodes(root_func))
        while stack:
            curr = stack.pop()
            yield curr
            if not isinstance(curr, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                stack.extend(ast.iter_child_nodes(curr))

    def _walk_scope(self, node, parent_locals: set[str]):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                combined_locals = parent_locals | self._collect_scope_locals(child)
                for sub in self._iter_function_body_nodes(child):
                    if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Load):
                        name = sub.id
                        if name not in combined_locals and name not in self.module_defs:
                            self.unresolved.append((child.name, sub.lineno, name))
                self._walk_scope(child, combined_locals)
            else:
                self._walk_scope(child, parent_locals)


def verify_python_files() -> list[str]:
    errors = []
    py_files = sorted(BACKEND_DIR.glob("*.py"))
    launcher = ROOT_DIR / "launcher_win.py"
    if launcher.exists():
        py_files.append(launcher)

    for py_file in py_files:
        try:
            py_compile.compile(str(py_file), doraise=True)
        except py_compile.PyCompileError as exc:
            errors.append(f"[SyntaxError] {py_file.name}: {exc}")
            continue

        source = py_file.read_text(encoding="utf-8")
        try:
            tree = ast.parse(source, filename=str(py_file))
        except SyntaxError as exc:
            errors.append(f"[AST SyntaxError] {py_file.name}:{exc.lineno}: {exc.msg}")
            continue

        analyzer = ScopeAnalyzer(py_file.name)
        analyzer.collect_top_level(tree)
        analyzer.check_functions(tree)
        for func_name, lineno, sym in analyzer.unresolved:
            errors.append(
                f"[UndefinedSymbol] {py_file.name}:{lineno} in `{func_name}()`: '{sym}' is not defined/imported"
            )

    return errors


def verify_qml_js_contracts() -> list[str]:
    errors = []
    shell_qml = ROOT_DIR / "shell.qml"
    social_js = COMPONENTS_DIR / "social_engine.js"
    playback_js = COMPONENTS_DIR / "playback_engine.js"

    for f in (shell_qml, social_js, playback_js):
        if not f.exists():
            errors.append(f"[MissingFile] {f.relative_to(ROOT_DIR)} does not exist")
            return errors

    shell_text = shell_qml.read_text(encoding="utf-8")
    social_text = social_js.read_text(encoding="utf-8")
    playback_text = playback_js.read_text(encoding="utf-8")

    social_funcs = set(re.findall(r"function\s+([A-Za-z0-9_]+)\s*\(", social_text))
    playback_funcs = set(re.findall(r"function\s+([A-Za-z0-9_]+)\s*\(", playback_text))

    for called in set(re.findall(r"SocialEngine\.([A-Za-z0-9_]+)\s*\(", shell_text)):
        if called not in social_funcs:
            errors.append(f"[MissingJSExport] SocialEngine.{called}() called in shell.qml but missing in social_engine.js")

    for called in set(re.findall(r"PlaybackEngine\.([A-Za-z0-9_]+)\s*\(", shell_text)):
        if called not in playback_funcs:
            errors.append(f"[MissingJSExport] PlaybackEngine.{called}() called in shell.qml but missing in playback_engine.js")

    return errors


def main() -> int:
    t0 = time.perf_counter()
    py_errors = verify_python_files()
    qml_errors = verify_qml_js_contracts()
    elapsed_ms = (time.perf_counter() - t0) * 1000.0

    all_errors = py_errors + qml_errors
    if all_errors:
        print(f"FAIL: {len(all_errors)} issue(s) detected in {elapsed_ms:.1f}ms:")
        for err in all_errors:
            print(f"  - {err}")
        return 1

    print(
        f"OK: All Python backend modules, AST symbol scopes, and QML/JS contracts verified in {elapsed_ms:.1f}ms."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
