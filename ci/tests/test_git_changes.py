import subprocess
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SELF_TEST = REPOSITORY_ROOT / "ci" / "impact" / "git_changes.py"


class GitChangeParserTests(unittest.TestCase):
    def test_nul_delimited_parser_covers_add_modify_delete_rename_and_copy(self) -> None:
        result = subprocess.run(
            ["python3", str(SELF_TEST), "--self-test"],
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("rename-copy-delete: passed", result.stdout)
        self.assertIn("malformed-input: passed", result.stdout)
        self.assertIn("fetch-ref-normalization: passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
