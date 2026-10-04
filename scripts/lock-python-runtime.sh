#!/bin/bash
# Re-resolves Runtime/requirements.lock from Runtime/requirements.in.
#
# MACOSX_DEPLOYMENT_TARGET matters: without it uv resolves for macOS 13, where
# mlx >= 0.31.2 publishes no wheels, and the resolution fails.
set -euo pipefail
cd "$(dirname "$0")/.."
MACOSX_DEPLOYMENT_TARGET=26.0 uv pip compile Runtime/requirements.in \
  --override Runtime/overrides.txt \
  --python-platform aarch64-apple-darwin \
  --python-version 3.14 \
  --generate-hashes \
  --no-config \
  --output-file Runtime/requirements.lock
