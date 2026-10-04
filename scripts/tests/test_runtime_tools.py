"""Tests for scripts/runtime_tools.py. Stdlib only: python3 -m unittest discover -s scripts/tests"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "scripts" / "runtime_tools.py"
sys.path.insert(0, str(TOOLS.parent))
import runtime_tools as rt  # noqa: E402


def make_prefix(tmp: Path) -> Path:
    """A fake python-build-standalone prefix with an empty site-packages."""
    prefix = tmp / "python"
    (prefix / "lib/python3.14/site-packages").mkdir(parents=True)
    (prefix / "lib/python3.14/LICENSE.txt").write_text("PSF LICENSE AGREEMENT FOR PYTHON\n")
    return prefix


def add_package(prefix: Path, name: str, version: str = "1.0", *, expression: str | None = None,
                classifiers: tuple[str, ...] = (), license_field: str | None = None,
                license_files: dict[str, str] | None = None) -> Path:
    site = prefix / "lib/python3.14/site-packages"
    dist = site / f"{name.replace('-', '_')}-{version}.dist-info"
    dist.mkdir()
    lines = ["Metadata-Version: 2.4", f"Name: {name}", f"Version: {version}"]
    if expression:
        lines.append(f"License-Expression: {expression}")
    if license_field:
        lines.append(f"License: {license_field}")
    lines += [f"Classifier: License :: {c}" for c in classifiers]
    (dist / "METADATA").write_text("\n".join(lines) + "\n\nLong description.\n")
    for fname, text in (license_files or {}).items():
        target = dist / "licenses" / fname
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return dist


class LicenseClassificationTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.prefix = make_prefix(Path(self._tmp.name))

    def tearDown(self):
        self._tmp.cleanup()

    def verdict(self, overrides: dict[str, str] | None = None) -> tuple[str, str]:
        [pkg] = rt.read_licenses(rt.site_packages(self.prefix))
        return rt.classify(pkg, overrides or {})

    def test_spdx_expression_is_ok(self):
        add_package(self.prefix, "numpy", expression="BSD-3-Clause")
        self.assertEqual(self.verdict(), ("ok", "BSD-3-Clause"))

    def test_gpl_expression_is_copyleft(self):
        add_package(self.prefix, "badpkg", expression="GPL-3.0-or-later")
        self.assertEqual(self.verdict()[0], "copyleft")

    def test_lgpl_classifier_is_copyleft(self):
        add_package(self.prefix, "badpkg",
                    classifiers=("OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)",))
        self.assertEqual(self.verdict()[0], "copyleft")

    def test_agpl_free_text_is_copyleft(self):
        add_package(self.prefix, "badpkg", license_field="GNU AFFERO GENERAL PUBLIC LICENSE")
        self.assertEqual(self.verdict()[0], "copyleft")

    def test_mpl_is_allowed(self):
        add_package(self.prefix, "certifi", classifiers=("OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)",))
        self.assertEqual(self.verdict()[0], "ok")

    def test_missing_license_is_unknown(self):
        add_package(self.prefix, "hf_transfer")
        self.assertEqual(self.verdict(), ("unknown", ""))

    def test_long_free_text_license_is_unknown(self):
        # A License field holding the whole license text, not a name, can't be trusted.
        add_package(self.prefix, "oddpkg", license_field="Copyright (c) 2010 Somebody. " * 5)
        self.assertEqual(self.verdict()[0], "unknown")

    def test_override_resolves_unknown_with_normalized_name(self):
        add_package(self.prefix, "hf_transfer")
        self.assertEqual(self.verdict({"hf-transfer": "Apache-2.0"}), ("ok", "Apache-2.0"))

    def test_non_ascii_metadata_does_not_crash(self):
        add_package(self.prefix, "intlpkg", expression="MIT", license_field="Licença MIT — © Ünïcode")
        self.assertEqual(self.verdict()[0], "ok")


class ForbiddenBinaryTests(unittest.TestCase):
    def test_finds_ffmpeg_and_x264_but_not_avif(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "cv2/.dylibs").mkdir(parents=True)
            for name in ("libavcodec.61.19.101.dylib", "libx264.164.dylib", "libswscale.8.dylib",
                         "libavif.16.3.0.dylib", "libdav1d.7.dylib"):
                (root / "cv2/.dylibs" / name).write_bytes(b"")
            found = sorted(p.name for p in rt.forbidden_binaries(root))
            self.assertEqual(found, ["libavcodec.61.19.101.dylib", "libswscale.8.dylib", "libx264.164.dylib"])


class GuardCLITests(unittest.TestCase):
    def run_guard(self, prefix: Path, overrides: dict[str, str]) -> subprocess.CompletedProcess:
        overrides_file = prefix.parent / "overrides.json"
        overrides_file.write_text(json.dumps(overrides))
        return subprocess.run([sys.executable, str(TOOLS), "guard", str(prefix), "--overrides", str(overrides_file)],
                              capture_output=True, text=True)

    def test_clean_runtime_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = make_prefix(Path(tmp))
            add_package(prefix, "numpy", expression="BSD-3-Clause")
            add_package(prefix, "hf_transfer")
            result = self.run_guard(prefix, {"_comment": "why", "hf-transfer": "Apache-2.0"})
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_copyleft_unknown_and_binaries_all_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = make_prefix(Path(tmp))
            add_package(prefix, "badpkg", expression="GPL-2.0-only")
            add_package(prefix, "mystery")
            (prefix / "lib/libx264.164.dylib").write_bytes(b"")
            result = self.run_guard(prefix, {})
            self.assertEqual(result.returncode, 1)
            self.assertIn("badpkg 1.0: copyleft license (GPL-2.0-only)", result.stderr)
            self.assertIn("mystery 1.0: no license metadata", result.stderr)
            self.assertIn("lib/libx264.164.dylib", result.stderr)


if __name__ == "__main__":
    unittest.main()
