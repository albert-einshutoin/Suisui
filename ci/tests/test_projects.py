import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ci.impact.projects import detect_projects


class ProjectDiscoveryTests(unittest.TestCase):
    def test_excluded_trees_are_never_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            for manifest in ('Package.swift', 'app/package.json', '.build/deep/package.json',
                             'app/node_modules/deep/package.json', 'rust/kokoro-helper/Cargo.toml'):
                path = repo / manifest
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            scanned = []
            scandir = os.scandir

            def track(path):
                scanned.append(Path(path).relative_to(repo).parts)
                return scandir(path)

            with patch('os.scandir', side_effect=track):
                projects = detect_projects(repo)
            self.assertEqual([p['manifest'] for p in projects], ['Package.swift', 'app/package.json'])
            self.assertFalse(any('.build' in parts or 'node_modules' in parts for parts in scanned))

    def test_scan_errors_are_not_successful_partial_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch('os.scandir', side_effect=PermissionError('unreadable project tree')):
                with self.assertRaises(PermissionError):
                    detect_projects(Path(directory))
