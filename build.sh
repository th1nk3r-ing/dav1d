#!/bin/bash
set -e

# ============================================================================
# build.sh - Build dav1d with analyzer (internals) extension
#
# Produces libdav1d.so / libdav1d.dylib (with dav1d_set_analyzer_flags
# exported) and optionally deploys it as libdav1d-internals.{so,dylib} next to
# YUViewApp.
#
# Environment variables (all optional):
#   DAV1D_DEPLOY_DIR - destination dir for libdav1d-internals.{so,dylib}
#                      (default: skip)
#
# Usage:
#   ./build.sh
#   DAV1D_DEPLOY_DIR=/path/to/YUViewApp ./build.sh
# ============================================================================

BUILD_DIR="${1:-build-internals}"

# --- ensure build tools are available ---
command -v meson  >/dev/null 2>&1 || { echo "[ERROR] meson not found. Install: pip install meson"; exit 1; }
command -v ninja  >/dev/null 2>&1 || { echo "[ERROR] ninja not found. pip install meson typically provides it."; exit 1; }
if ! command -v nasm >/dev/null 2>&1; then
  echo "[WARNING] nasm not found; ASM optimizations will be disabled."
fi

# --- meson setup ---
echo "=== meson setup ==="
meson setup "$BUILD_DIR" \
  --default-library=shared \
  --buildtype=release \
  -Denable_asm=true \
  -Denable_tools=false \
  -Denable_tests=false

# --- ninja build ---
echo "=== ninja build ==="
ninja -C "$BUILD_DIR"

# --- verify analyzer exports ---
echo "=== verify analyzer exports ==="
LIBEXT=so
if [ "$(uname)" = "Darwin" ]; then LIBEXT=dylib; fi

# dav1d ships with soname versioning (libdav1d.so.<api_major>), so the plain
# libdav1d.so symlink lives in src/ alongside the versioned files.
SRC_LIB="$BUILD_DIR/src/libdav1d.$LIBEXT"
if [ ! -f "$SRC_LIB" ]; then
  # fall back to a versioned name if the plain symlink wasn't created
  SRC_LIB=$(ls "$BUILD_DIR"/src/libdav1d.$LIBEXT.* 2>/dev/null | head -n1)
fi
if [ -z "$SRC_LIB" ] || [ ! -f "$SRC_LIB" ]; then
  echo "[ERROR] dav1d library not found in $BUILD_DIR/src/"
  exit 1
fi

if ! (nm -D "$SRC_LIB" 2>/dev/null || nm "$SRC_LIB" 2>/dev/null) | grep -q "dav1d_set_analyzer_flags"; then
  echo "[ERROR] dav1d_set_analyzer_flags not exported; build is not the internals variant."
  exit 1
fi
echo "[ok] dav1d_set_analyzer_flags exported"

# --- optional deploy ---
if [ -n "$DAV1D_DEPLOY_DIR" ]; then
  if [ ! -d "$DAV1D_DEPLOY_DIR" ]; then
    echo "[WARNING] DAV1D_DEPLOY_DIR does not exist, skipping deploy: $DAV1D_DEPLOY_DIR"
  else
    echo "=== deploy to $DAV1D_DEPLOY_DIR ==="
    cp -f "$SRC_LIB" "$DAV1D_DEPLOY_DIR/libdav1d-internals.$LIBEXT"
  fi
else
  echo "=== deploy skipped (set DAV1D_DEPLOY_DIR to enable) ==="
fi

echo "=== done: $SRC_LIB ==="
