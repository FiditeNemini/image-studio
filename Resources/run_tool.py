"""Runs a bundled package's command-line tool by name.

    python3.14 run_tool.py <tool-name> [args...]

<tool-name> is a console-script name such as `mflux-generate-flux2` or `hf`. It
is looked up in the interpreter's installed package metadata, so the app never
depends on the launcher scripts in bin/, whose shebangs hold absolute paths
that break once the runtime is copied into the app bundle. Exit semantics match
those launchers exactly: sys.exit(<tool's return value>).
"""

import sys
from importlib.metadata import entry_points


def main(argv):
    if len(argv) < 2:
        print("usage: run_tool.py <tool-name> [args...]", file=sys.stderr)
        return 2
    name = argv[1]
    matches = entry_points(group="console_scripts", name=name)
    if not matches:
        print(f"run_tool.py: no installed tool named {name!r}", file=sys.stderr)
        return 127
    tool = next(iter(matches)).load()
    sys.argv = [name, *argv[2:]]
    return tool()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
