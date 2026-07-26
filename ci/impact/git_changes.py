#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path
from typing import Dict, List


class GitChangeError(RuntimeError):
    pass


def parse_name_status_z(raw: bytes) -> List[Dict[str, str]]:
    tokens = raw.split(b"\0")
    if tokens and tokens[-1] == b"":
        tokens.pop()
    changes: List[Dict[str, str]] = []
    index = 0
    while index < len(tokens):
        try:
            status = tokens[index].decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise GitChangeError("git diff status is not valid UTF-8") from error
        index += 1
        if not status or status[0] not in "ACDMRTUXB":
            raise GitChangeError("git diff returned an unsupported status")
        path_count = 2 if status[0] in "RC" else 1
        if index + path_count > len(tokens):
            raise GitChangeError("git diff returned a truncated record")
        try:
            paths = [
                tokens[index + offset].decode("utf-8", errors="strict")
                for offset in range(path_count)
            ]
        except UnicodeDecodeError as error:
            raise GitChangeError("git diff path is not valid UTF-8") from error
        if any(not path for path in paths):
            raise GitChangeError("git diff returned an empty path")
        index += path_count
        if path_count == 2:
            changes.append({"status": status, "oldPath": paths[0], "path": paths[1]})
        else:
            changes.append({"status": status, "path": paths[0]})
    return changes


def _run(repo: Path, arguments: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        arguments,
        cwd=str(repo),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def collect_changes(repo: Path, base_revision: str, head_revision: str) -> Dict[str, object]:
    shallow_path = _run(repo, ["git", "rev-parse", "--git-path", "shallow"])
    if shallow_path.returncode != 0:
        raise GitChangeError("could not inspect shallow clone state")
    shallow_file = repo / shallow_path.stdout.decode("utf-8").strip()
    if shallow_file.exists():
        # A partial graph can yield a plausible but wrong merge base, so recover
        # the complete history before any attempt to select fewer tests.
        unshallow = _run(repo, ["git", "fetch", "--no-tags", "--unshallow", "origin"])
        if unshallow.returncode != 0:
            raise GitChangeError("shallow history recovery failed")

    merge_base = _run(repo, ["git", "merge-base", base_revision, head_revision])
    if merge_base.returncode != 0:
        fetch_base = _run(repo, ["git", "fetch", "--no-tags", "origin", base_revision])
        if fetch_base.returncode != 0:
            raise GitChangeError("base revision fetch failed")
        merge_base = _run(repo, ["git", "merge-base", base_revision, head_revision])
    if merge_base.returncode != 0:
        raise GitChangeError("base revision merge-base resolution failed")
    resolved_base = merge_base.stdout.decode("ascii", errors="strict").strip()
    if not resolved_base:
        raise GitChangeError("base revision merge-base was empty")

    diff = _run(
        repo,
        [
            "git",
            "diff",
            "--name-status",
            "-z",
            "--find-renames",
            "--find-copies",
            resolved_base,
            head_revision,
            "--",
        ],
    )
    if diff.returncode != 0:
        raise GitChangeError("changed file discovery failed")
    return {"baseRevision": resolved_base, "changes": parse_name_status_z(diff.stdout)}


def _self_test() -> int:
    raw = (
        b"A\0added.swift\0"
        b"M\0changed.swift\0"
        b"D\0deleted.swift\0"
        b"R100\0old.swift\0new.swift\0"
        b"C095\0source.swift\0copy.swift\0"
    )
    parsed = parse_name_status_z(raw)
    assert [item["status"] for item in parsed] == ["A", "M", "D", "R100", "C095"]
    assert parsed[3]["oldPath"] == "old.swift"
    assert parsed[3]["path"] == "new.swift"
    print("rename-copy-delete: passed")
    try:
        parse_name_status_z(b"R100\0only-one-path\0")
    except GitChangeError:
        print("malformed-input: passed")
        return 0
    print("malformed-input: failed", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return _self_test()
    parser.error("--self-test is required when invoking this module directly")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
