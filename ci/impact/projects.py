from pathlib import Path
from typing import Dict, List, Set, Tuple


MANIFEST_TYPES = {
    "Package.swift": ("swift", "swiftpm"),
    "package.json": ("javascript", "node"),
    "pyproject.toml": ("python", "python"),
    "setup.py": ("python", "python"),
    "go.mod": ("go", "go"),
    "Cargo.toml": ("rust", "cargo"),
    "pom.xml": ("jvm", "maven"),
    "build.gradle": ("jvm", "gradle"),
    "build.gradle.kts": ("jvm", "gradle"),
}
EXCLUDED_DIRECTORIES = {
    ".build",
    ".git",
    ".swiftpm",
    ".tmp",
    "node_modules",
    "vendor",
}


def detect_projects(repo: Path) -> List[Dict[str, str]]:
    detected: Dict[Tuple[str, str], Dict[str, str]] = {}
    for path in repo.rglob("*"):
        if any(part in EXCLUDED_DIRECTORIES for part in path.relative_to(repo).parts):
            continue
        if not path.is_file() or path.name not in MANIFEST_TYPES:
            continue
        project_type, tool = MANIFEST_TYPES[path.name]
        project_path = path.parent.relative_to(repo).as_posix() or "."
        key = (project_path, project_type)
        detected[key] = {
            "path": project_path,
            "type": project_type,
            "tool": tool,
            "manifest": path.relative_to(repo).as_posix(),
            "adapter": "swift" if project_type == "swift" else "unsupported",
        }
    return sorted(detected.values(), key=lambda item: (item["path"], item["type"]))


def unsupported_project_types(projects: List[Dict[str, str]]) -> Set[str]:
    return {project["type"] for project in projects if project["adapter"] == "unsupported"}
