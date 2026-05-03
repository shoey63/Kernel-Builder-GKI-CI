#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
mkdir -p ../out out/dist

[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }
[ -x tools/bazel ] || { echo "[-] tools/bazel not found or not executable" >&2; exit 1; }

echo ">>> Neutralizing ABI protected exports lists..."
for f in common/android/abi_gki_protected_exports*; do
  if [ -f "$f" ]; then
    > "$f"
  fi
done

echo ">>> Removing '-dirty' flag from kernel release string..."
sed -i "s/printf '%s' -dirty/printf '%s' ''/g" common/scripts/setlocalversion

echo ">>> Foiling Kleaf's 1970 build date..."
# Generate a formatted date string (e.g., "Sun May 03 18:55:24 UTC 2026")
CURRENT_DATE=$(date -u +"%a %b %d %H:%M:%S UTC %Y")

# Replace the default timestamp logic in the 6.1+ Makefile
sed -i "s/build-timestamp = \$(or \$(KBUILD_BUILD_TIMESTAMP), \$(build-timestamp-auto))/build-timestamp = \"$CURRENT_DATE\"/g" common/init/Makefile

echo ">>> Compiling common Android arm64 kernel..."
tools/bazel run --config=local --config=stamp //common:kernel_aarch64_dist -- --destdir=out/dist

IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1)"

if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
  echo "[-] No Image produced by common kernel build" >&2
  exit 1
fi

echo ">>> Selected Image: ${IMAGE_PATH}"
cp -f "${IMAGE_PATH}" ../out/Image

echo ">>> Build complete!"
