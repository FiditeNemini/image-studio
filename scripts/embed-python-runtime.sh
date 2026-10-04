#!/bin/bash
# Xcode post-build phase: puts the bundled Python runtime into the app.
#
# Builds the runtime if needed (no-op when cached), signs a copy once per
# (runtime, flavor, identity, signing inputs) under OBJROOT, then rsyncs that
# copy into Contents/Resources/python. Later builds only rsync, which skips
# unchanged files. Signed copies of older runtimes are deleted.
set -euo pipefail

if [ "${BUNDLE_PYTHON_RUNTIME:-NO}" != "YES" ]; then
  echo "Python runtime: not bundled in $CONFIGURATION"
  exit 0
fi

"$SRCROOT/scripts/build-python-runtime.sh"
RUNTIME="$SRCROOT/build/python-runtime"
KEY=$(cat "$RUNTIME/cache-key")

FLAVOR=plain
if [ "${PYTHON_RUNTIME_SANDBOXED:-NO}" = "YES" ]; then FLAVOR=sandboxed; fi
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then IDENTITY=""; fi
SIGN_INPUTS=$(cat "$SRCROOT/scripts/sign-python-runtime.sh" "$SRCROOT/Resources/PythonRuntime-Sandboxed.entitlements" \
  | shasum -a 256 | cut -c1-8)

STAGES="$OBJROOT/PythonRuntimeSigned"
STAGE="$STAGES/$KEY-$FLAVOR-${IDENTITY:-unsigned}-$SIGN_INPUTS"
mkdir -p "$STAGES"
for old in "$STAGES"/*; do
  [ -e "$old" ] || continue
  case "$(basename "$old")" in
    "$KEY"-*) ;;          # current runtime: keep every flavor/identity
    *) rm -rf "$old" ;;   # an older runtime
  esac
done

if [ ! -f "$STAGE/.complete" ]; then
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  ditto "$RUNTIME/python" "$STAGE/python"
  if [ -n "$IDENTITY" ]; then
    "$SRCROOT/scripts/sign-python-runtime.sh" "$STAGE/python" "$IDENTITY" "$FLAVOR" "$CONFIGURATION"
  fi
  touch "$STAGE/.complete"  # last: a killed signing pass is redone next build
fi

DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/python"
mkdir -p "$DEST"
rsync -a --delete "$STAGE/python/" "$DEST/"
echo "Python runtime embedded ($KEY, $FLAVOR, ${IDENTITY:-unsigned})"
