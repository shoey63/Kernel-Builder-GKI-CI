#!/bin/bash
set -e

# --- Configuration ---
WORKSPACE="workspace"
DIST_DIR="out/dist"

cd "${WORKSPACE}"

echo "=== Applying ABI Fixes ==="
echo "Neutralizing ABI protected exports for Pixel compatibility..."
> common/android/abi_gki_protected_exports_aarch64
> common/android/abi_gki_protected_exports_x86_64

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
# Move the Image to the root of the workspace for a clean zip structure
mv "${DIST_DIR}/Image" ./Image

echo "=== Build Complete ==="
