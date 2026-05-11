#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
mkdir -p ../out out/dist

[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }
[ -x tools/bazel ] || { echo "[-] tools/bazel not found or not executable" >&2; exit 1; }

# Capture the PURE Google head 
GKI_HASH=$(git rev-parse --short HEAD)
GKI_DATE=$(git log -1 --format=%ct)

echo ">>> Latest commit Locked: g$GKI_HASH (Timestamp: $GKI_DATE)"

echo ">>> Neutralizing ABI protected exports lists..."
for f in common/android/abi_gki_protected_exports*; do
  if [ -f "$f" ]; then
    > "$f"
  fi
done

echo ">>> Satisfying Kleaf's git status checks to remove -dirty and fix timestamp..."
cd common

# Configure local git identity
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

# Stage and commit changes
git add .
git commit -m "ci: integrated KSU, SUSFS, and other patches if any" || true
cd ..

echo ">>> Compiling common Android arm64 kernel..."

tools/bazel run --config=local --config=stamp \
  --action_env=SOURCE_DATE_EPOCH="$GKI_DATE" \
  --action_env=STABLE_BUILD_VERSION="g$GKI_HASH" \
  --action_env=KLEAF_KERNEL_BUILD_VERSION="g$GKI_HASH" \
  --action_env=KLEAF_SKIP_ABI_CHECKS=true \
  //common:kernel_aarch64_dist -- --destdir=out/dist

IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1)"

if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
  echo "[-] No Image produced by common kernel build" >&2
  exit 1
fi

echo ">>> Selected Image: ${IMAGE_PATH}"
cp -f "${IMAGE_PATH}" ../out/Image

echo ">>> Extracting compiled kernel version string..."
strings ../out/Image | grep "Linux version" | head -n 1

echo ">>> Build complete!"
