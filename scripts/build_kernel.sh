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

# ====================== WIREGUARD SUPPORT ======================
echo ">>> Setting up WireGuard defconfig fragment..."

cd common

cat > wireguard_fragment << 'EOF'
# WireGuard support
CONFIG_WIREGUARD=y
CONFIG_NET_UDP_TUNNEL=y
CONFIG_CRYPTO_CURVE25519=y
CONFIG_CRYPTO_CURVE25519_X86=y
EOF

# Export the fragment so Bazel can see it
echo 'exports_files(["wireguard_fragment"])' >> BUILD.bazel

echo ">>> WireGuard fragment created:"
cat wireguard_fragment
echo ">>> ---------------------------------------------------"
cd ..
# ============================================================

echo ">>> Marking repo as clean..."
cd common
git ls-files -m | xargs -r git update-index --assume-unchanged
cd ..

echo ">>> Collecting Latest Hash and Commencing build: g$OFFICIAL_HASH"

tools/bazel run --config=local --config=stamp \
  --action_env=SOURCE_DATE_EPOCH="$OFFICIAL_DATE" \
  --action_env=STABLE_BUILD_VERSION="g$OFFICIAL_HASH" \
  --action_env=KLEAF_KERNEL_BUILD_VERSION="g$OFFICIAL_HASH" \
  --action_env=KLEAF_SKIP_ABI_CHECKS=true \
  //common:kernel_aarch64_dist \
  -- \
  --post_defconfig_fragments=//common:wireguard_fragment \
  --destdir=out/dist

IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1)"

if [ -z "\( {IMAGE_PATH}" ] || [ ! -f " \){IMAGE_PATH}" ]; then
  echo "[-] No Image produced by common kernel build" >&2
  exit 1
fi

echo ">>> Selected Image: ${IMAGE_PATH}"
cp -f "${IMAGE_PATH}" ../out/Image

echo ">>> Extracting compiled kernel version string..."
strings ../out/Image | grep "Linux version" | head -n 1

echo ">>> Checking for WireGuard symbols in Image..."
if strings ../out/Image | grep -qi "wireguard"; then
    echo ">>> SUCCESS: WireGuard symbols found in Image binary."
else
    echo ">>> WARNING: WireGuard symbols not found in final Image."
fi

echo ">>> Build complete!"
