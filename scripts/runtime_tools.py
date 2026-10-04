#!/usr/bin/env python3
"""Build-time helpers for the Python runtime bundled into MLXBits Image Studio.

    runtime_tools.py guard <prefix> --overrides FILE
        Exit 1 if any installed package is GPL-family licensed or has no license
        metadata (and no entry in FILE), or if a GPL-family native library
        (FFmpeg, x264) is anywhere under <prefix>.

Stdlib only. The runtime build runs this with the bundled interpreter; the unit
tests run it with any python3 >= 3.10.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from email.parser import BytesParser
from email.policy import compat32
from pathlib import Path

COPYLEFT = re.compile(r"\b(A?GPL|LGPL)\b|GNU (AFFERO |LESSER |LIBRARY )?GENERAL PUBLIC", re.IGNORECASE)
# FFmpeg's libraries and the x264/x265 encoders. libavif (AV1 images, BSD) is fine.
FORBIDDEN_BINARY = re.compile(r"^lib(av(codec|format|util|device|filter)|sw(scale|resample)|postproc|x264|x265)\b")
# A License field longer than this is license *text*, not a license name.
MAX_LICENSE_NAME = 80


@dataclass(frozen=True)
class PackageLicense:
    name: str
    version: str
    license: str  # best-effort license name; "" when the metadata has none
    dist_info: Path


def normalize(name: str) -> str:
    """PEP 503 name normalization: hf_transfer, HF.Transfer and hf-transfer are one package."""
    return re.sub(r"[-_.]+", "-", name).lower()


def site_packages(prefix: Path) -> Path:
    matches = sorted(prefix.glob("lib/python3.*/site-packages"))
    if not matches:
        raise SystemExit(f"error: no lib/python3.*/site-packages under {prefix}")
    return matches[0]


def read_licenses(site: Path) -> list[PackageLicense]:
    packages = []
    for meta in sorted(site.glob("*.dist-info/METADATA")):
        with meta.open("rb") as fh:
            msg = BytesParser(policy=compat32).parse(fh)

        def field(key: str) -> str:
            return str(msg.get(key) or "").strip()  # str(): non-ASCII values parse as Header objects

        classifiers = [str(c).split("::")[-1].strip()
                       for c in msg.get_all("Classifier") or [] if str(c).startswith("License ::")]
        free_text = field("License")
        first_line = free_text.splitlines()[0].strip() if free_text else ""
        best = (field("License-Expression") or "; ".join(classifiers)
                or (first_line if len(first_line) <= MAX_LICENSE_NAME else ""))
        packages.append(PackageLicense(field("Name"), field("Version"), best, meta.parent))
    return packages


def classify(pkg: PackageLicense, overrides: dict[str, str]) -> tuple[str, str]:
    license_name = overrides.get(normalize(pkg.name), pkg.license)
    if not license_name:
        return "unknown", ""
    if COPYLEFT.search(license_name):
        return "copyleft", license_name
    return "ok", license_name


def forbidden_binaries(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*") if p.is_file() and FORBIDDEN_BINARY.match(p.name))


def load_overrides(path: Path) -> dict[str, str]:
    raw = json.loads(path.read_text())
    return {normalize(k): v for k, v in raw.items() if not k.startswith("_")}


def guard(prefix: Path, overrides_file: Path) -> list[str]:
    overrides = load_overrides(overrides_file)
    problems = []
    for pkg in read_licenses(site_packages(prefix)):
        verdict, license_name = classify(pkg, overrides)
        if verdict == "copyleft":
            problems.append(f"{pkg.name} {pkg.version}: copyleft license ({license_name})")
        elif verdict == "unknown":
            problems.append(f"{pkg.name} {pkg.version}: no license metadata; check it by hand "
                            f"and record it in {overrides_file.name}")
    problems += [f"GPL-family native library: {p.relative_to(prefix)}" for p in forbidden_binaries(prefix)]
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_guard = sub.add_parser("guard")
    p_guard.add_argument("prefix", type=Path)
    p_guard.add_argument("--overrides", type=Path, required=True)
    args = parser.parse_args(argv)

    if args.command == "guard":
        problems = guard(args.prefix, args.overrides)
        for line in problems:
            print(f"license guard: {line}", file=sys.stderr)
        return 1 if problems else 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
