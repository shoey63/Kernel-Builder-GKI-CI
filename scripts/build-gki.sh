#!/bin/bash
set -e

WORKSPACE="workspace"
DIST_DIR="out/dist"

cd "${WORKSPACE}"

echo "=== Applying ABI Fixes ==="
> common/android/abi_gki_protected_exports_aarch64
> common/android/abi_gki_protected_exports_x86_64

echo "=== Integrating KernelSU-Next ==="
git clone https://github.com/shoey63/KernelSU-Next.git -b pixel9-susfs-gki-android14-6.1 KernelSU-Next

bash KernelSU-Next/kernel/setup.sh

echo "Restoring the custom pixel9-susfs branch..."
cd KernelSU-Next
git checkout pixel9-susfs-gki-android14-6.1

# --- THE VERSION FIX ---
echo "Grabbing Git info for KSU manager..."
KSU_TAG=$(git describe --abbrev=0 --tags 2>/dev/null || echo "v1.0.0")
KSU_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# --- HARD DEBUG TRAP ---
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "pixel9-susfs-gki-android14-6.1" ]; then
    echo "CRITICAL ERROR: KernelSU-Next branch hijack detected!"
    exit 1
fi
cd ..

echo "Replacing KSU symlink with a hard copy for the Bazel sandbox..."
rm -f common/drivers/kernelsu
cp -r KernelSU-Next/kernel common/drivers/kernelsu

# --- THE UAPI FIX ---
echo "Hunting down missing uapi headers..."
UAPI_DIR=$(find KernelSU-Next -type d -name "uapi" | head -n 1)
if [ -n "$UAPI_DIR" ]; then
    echo "Found uapi at $UAPI_DIR, injecting into sandbox sightlines..."
    cp -r "$UAPI_DIR" common/drivers/kernelsu/
    cp -r "$UAPI_DIR" common/drivers/
else
    echo "WARNING: Could not find uapi folder in KernelSU-Next!"
fi

echo "Injecting KSU Git versions to silence Kbuild warnings..."
sed -i "1i KSU_GIT_VERSION := $KSU_HASH" common/drivers/kernelsu/Kbuild
sed -i "1i KSU_VERSION_TAG := $KSU_TAG" common/drivers/kernelsu/Kbuild

# Strip config constraints
sed -i '/default [yn]/d' common/drivers/kernelsu/Kconfig || true
sed -i 's/^config .*/&\n\tdefault y/g' common/drivers/kernelsu/Kconfig || true

echo "=== Integrating susfs4ksu ==="
# Pointing directly to your new, split-patch branch!
git clone https://gitlab.com/shoey63/susfs4ksu.git -b android-14-patchfix susfs4ksu

cp -r susfs4ksu/kernel_patches/fs/* common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "Applying susfs kernel patches..."
cd common
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_*.patch .
# Removing the "|| true" so we can see if the split patch succeeds natively!
patch -p1 < 50_add_susfs_in_*.patch
cd ..

# --- UPSTREAM BUG FIX ---
echo "Fixing upstream typo in KernelSU-Next allowlist.c..."
sed -i 's/\.current_uid/.curr_uid/g' common/drivers/kernelsu/policy/allowlist.c || true

echo "======================================================="
echo "=== SUSFS / KSU INJECTION AUDIT (PRE-BUILD CHECK) ==="
echo "======================================================="
echo "--> 1. Verifying manual Hunk #1 injection in fs/namespace.c:"
grep -A 5 -B 2 "static DEFINE_IDA(susfs_mnt_id_ida);" common/fs/namespace.c
echo -e "\n--> 2. Verifying forced KSU configurations:"
grep -A 2 "config KSU_SUSFS$" common/drivers/kernelsu/Kconfig
echo -e "\n--> 3. Checking uapi header injection:"
ls -l common/drivers/kernelsu/uapi | head -n 3
echo "======================================================="

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Fetching Stock Boot Image ==="
# !!! REPLACE THIS URL WITH YOUR SPECIFIC OTA LINK !!!
python3 scripts/ota_pull.py \
  --source "https://dl.google.com/dl/android/aosp/komodo-ota-cp1a.260405.005-62a6d5ce.zip" \
  --partition boot \
  --outdir ./stock_boot

echo "=== Repacking Custom Boot Image ==="
chmod +x tools/magiskboot
chmod +x scripts/boot_swap.sh

scripts/boot_swap.sh \
  --boot ./stock_boot/boot-*.img \
  --image ./Image \
  --magiskboot tools/magiskboot \
  --outdir ./ \
  --outname "pixel9-susfs-patched-boot.img"

echo "=== Assembly Complete ==="
