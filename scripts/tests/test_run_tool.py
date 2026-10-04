"""Tests for Resources/run_tool.py, using a fake installed package on PYTHONPATH."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

RUN_TOOL = Path(__file__).resolve().parents[2] / "Resources" / "run_tool.py"

FAKE_MODULE = '''
import sys

def echo():
    print(repr(sys.argv))
    return 3

def quiet():
    return None

def complain():
    return "something went wrong"
'''


class RunToolTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        site = Path(self._tmp.name)
        (site / "fakepkg").mkdir()
        (site / "fakepkg/__init__.py").write_text(FAKE_MODULE)
        dist = site / "fakepkg-1.0.dist-info"
        dist.mkdir()
        (dist / "METADATA").write_text("Metadata-Version: 2.1\nName: fakepkg\nVersion: 1.0\n")
        (dist / "entry_points.txt").write_text(
            "[console_scripts]\nfake-echo = fakepkg:echo\nfake-quiet = fakepkg:quiet\n"
            "fake.complain = fakepkg:complain\n")
        self.env = {**os.environ, "PYTHONPATH": str(site), "PYTHONDONTWRITEBYTECODE": "1"}

    def tearDown(self):
        self._tmp.cleanup()

    def run_tool(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(RUN_TOOL), *args], capture_output=True, text=True, env=self.env)

    def test_passes_name_and_arguments_as_argv_and_returns_exit_code(self):
        result = self.run_tool("fake-echo", "--flag", "two words")
        self.assertEqual(result.stdout.strip(), repr(["fake-echo", "--flag", "two words"]))
        self.assertEqual(result.returncode, 3)

    def test_none_exits_zero(self):
        self.assertEqual(self.run_tool("fake-quiet").returncode, 0)

    def test_string_result_is_printed_and_exits_one(self):
        result = self.run_tool("fake.complain")
        self.assertEqual(result.returncode, 1)
        self.assertIn("something went wrong", result.stderr)

    def test_unknown_tool_exits_127(self):
        result = self.run_tool("no-such-tool")
        self.assertEqual(result.returncode, 127)
        self.assertIn("no-such-tool", result.stderr)

    def test_no_arguments_prints_usage_and_exits_2(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: run_tool.py", result.stderr)


if __name__ == "__main__":
    unittest.main()
