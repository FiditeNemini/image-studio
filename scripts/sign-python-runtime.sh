#!/bin/bash
# Signs every Mach-O file in a copy of the bundled Python runtime.
#
#   sign-python-runtime.sh <runtime-dir> <identity> <plain|sandboxed> <configuration>
#
#   identity       codesign identity (SHA-1 or name); "-" signs ad-hoc
#   flavor         sandboxed: executables get the sandbox-inherit pair (App Store
#                  build). plain: no entitlements (DMG build), because the inherit
#                  pair crashes a child of an unsandboxed app.
#   configuration  Release* gets a secure timestamp (notarization requires one)
#
# Ad-hoc signatures skip the hardened runtime: library validation rejects
# ad-hoc-signed libraries under it, and Python could not load its own modules.
# Plain strings instead of arrays throughout: macOS bash 3.2 with set -u aborts
# on an empty "${array[@]}".
set -euo pipefail

DIR="$1"; IDENTITY="$2"; FLAVOR="$3"; CONFIGURATION="$4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(sed -n 's/^version=//p' "$ROOT/Runtime/python.lock")
# The unsigned build output is runnable here; the copy being signed may not be.
SCANNER="$ROOT/build/python-runtime/python/bin/python${VERSION%.*}"
ENTITLEMENTS="$ROOT/Resources/PythonRuntime-Sandboxed.entitlements"

case "$FLAVOR" in
  sandboxed|plain) ;;
  *) echo "error: flavor must be 'plain' or 'sandboxed', got '$FLAVOR'" >&2; exit 2 ;;
esac

# Word-split on purpose below: flags only, never paths.
OPTS="--force --sign $IDENTITY"
if [ "$IDENTITY" != "-" ]; then OPTS="$OPTS --options runtime"; fi
if [ "$IDENTITY" != "-" ] && [[ "$CONFIGURATION" == Release* ]]; then
  OPTS="$OPTS --timestamp"
else
  OPTS="$OPTS --timestamp=none"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$SCANNER" "$ROOT/scripts/runtime_tools.py" macho "$DIR" >"$WORK/list"

# Libraries: 8 codesign processes at a time. xargs exits non-zero if any
# signing fails; codesign's chatter ("replacing existing signature") goes to a
# log that is shown only on failure.
if ! grep $'^lib\t' "$WORK/list" | cut -f2- | tr '\n' '\0' \
    | xargs -0 -n 16 -P 8 codesign $OPTS >"$WORK/libs.log" 2>&1; then
  grep -v "replacing existing signature" "$WORK/libs.log" >&2 || true
  echo "error: signing the runtime's libraries failed" >&2
  exit 1
fi

# Executables (python3.14, torch_shm_manager), after the libraries they load.
grep $'^exe\t' "$WORK/list" | cut -f2- >"$WORK/exes"
while IFS= read -r exe; do
  if [ "$FLAVOR" = sandboxed ]; then
    codesign $OPTS --entitlements "$ENTITLEMENTS" "$exe" 2>"$WORK/exe.log" || { cat "$WORK/exe.log" >&2; exit 1; }
  else
    codesign $OPTS "$exe" 2>"$WORK/exe.log" || { cat "$WORK/exe.log" >&2; exit 1; }
  fi
done <"$WORK/exes"

echo "Signed $(grep -c . "$WORK/list") Mach-O files ($FLAVOR, identity ${IDENTITY:0:8})"
