import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set


DECLARATION_PATTERN = re.compile(
    r"\b(?:actor|class|enum|protocol|struct|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
TOKEN_PATTERN = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
TEST_SUITE_DECLARATION_PATTERN = re.compile(
    r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*Tests)\b"
)


class SwiftAnalysisError(RuntimeError):
    pass


def _target_dependencies(target: dict) -> Set[str]:
    dependencies: Set[str] = set()
    for dependency in target.get("dependencies", []):
        if not isinstance(dependency, dict):
            raise SwiftAnalysisError("Swift dependency graph contains an invalid dependency")
        by_name = dependency.get("byName")
        if isinstance(by_name, list) and by_name and isinstance(by_name[0], str):
            dependencies.add(by_name[0])
    return dependencies


def parse_target_graph(package_graph: dict) -> Dict[str, Set[str]]:
    targets = package_graph.get("targets")
    if not isinstance(targets, list):
        raise SwiftAnalysisError("Swift dependency graph targets are invalid")
    graph: Dict[str, Set[str]] = {}
    for target in targets:
        if not isinstance(target, dict) or not isinstance(target.get("name"), str):
            raise SwiftAnalysisError("Swift dependency graph target is invalid")
        graph[target["name"]] = _target_dependencies(target)
    if not graph:
        raise SwiftAnalysisError("Swift dependency graph is empty")
    return graph


def target_for_path(path: str, graph: Dict[str, Set[str]]) -> Optional[str]:
    parts = Path(path).parts
    if len(parts) >= 2 and parts[0] == "Tests":
        return parts[1] if parts[1] in graph else None
    if len(parts) >= 2 and parts[0] == "Sources":
        directory = parts[1]
        aliases = {"SuisuiApp": "Suisui"}
        candidate = aliases.get(directory, directory)
        return candidate if candidate in graph else None
    return None


def reverse_dependency_closure(
    changed_targets: Iterable[str], graph: Dict[str, Set[str]]
) -> Set[str]:
    affected = set(changed_targets)
    changed = True
    while changed:
        changed = False
        for target, dependencies in graph.items():
            if target not in affected and dependencies.intersection(affected):
                affected.add(target)
                changed = True
    return affected


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise SwiftAnalysisError("Swift source could not be read as UTF-8") from error


def _declared_symbols(text: str) -> Set[str]:
    return set(DECLARATION_PATTERN.findall(text))


def _tokens(text: str) -> Set[str]:
    return set(TOKEN_PATTERN.findall(text))


def _declared_test_suites(text: str) -> Set[str]:
    return set(TEST_SUITE_DECLARATION_PATTERN.findall(text))


def select_tests(repo: Path, changed_paths: List[str]) -> Dict[str, List[str]]:
    changed_test_paths = [
        path
        for path in changed_paths
        if path.startswith("Tests/") and path.endswith(".swift")
    ]
    changed_source_paths = [
        path
        for path in changed_paths
        if path.startswith("Sources/") and path.endswith(".swift")
    ]
    unit_targets: Set[str] = set()
    for relative_path in changed_test_paths:
        test_file = repo / relative_path
        if not test_file.is_file():
            raise SwiftAnalysisError("changed Swift test does not exist")
        unit_targets.update(_declared_test_suites(_read_text(test_file)))

    source_files = sorted((repo / "Sources").rglob("*.swift"))
    test_files = sorted((repo / "Tests").rglob("*.swift"))
    declarations_by_source: Dict[Path, Set[str]] = {}
    tokens_by_source: Dict[Path, Set[str]] = {}
    for source_file in source_files:
        text = _read_text(source_file)
        declarations_by_source[source_file] = _declared_symbols(text)
        tokens_by_source[source_file] = _tokens(text)

    impacted_files: Set[Path] = set()
    impacted_symbols: Set[str] = set()
    for relative_path in changed_source_paths:
        source_file = repo / relative_path
        if not source_file.is_file():
            raise SwiftAnalysisError("changed Swift source does not exist")
        impacted_files.add(source_file)
        impacted_symbols.update(declarations_by_source.get(source_file, set()))

    # Swift files inside one target do not import each other. Following declared
    # symbol references provides a conservative intra-target reverse graph while
    # Package.swift supplies the inter-target reverse graph.
    grew = True
    while grew and impacted_symbols:
        grew = False
        for source_file, tokens in tokens_by_source.items():
            if source_file in impacted_files or not tokens.intersection(impacted_symbols):
                continue
            impacted_files.add(source_file)
            new_symbols = declarations_by_source[source_file] - impacted_symbols
            if new_symbols:
                impacted_symbols.update(new_symbols)
            grew = True

    for test_file in test_files:
        text = _read_text(test_file)
        if _tokens(text).intersection(impacted_symbols):
            # SwiftPM filters XCTest suite names, not filenames. Support files
            # live beside suites and may reference the same production symbols;
            # emitting their stems would execute zero tests and must fail closed.
            unit_targets.update(_declared_test_suites(text))

    return {
        "unitTestTargets": sorted(unit_targets),
        "impactedSourceFiles": sorted(
            path.relative_to(repo).as_posix() for path in impacted_files
        ),
        "impactedSymbols": sorted(impacted_symbols),
    }
