#!/bin/bash
set -e

WORKSPACE="workspace"
DIST_DIR="out/dist"

cd "${WORKSPACE}"

echo "=== Applying ABI Fixes ==="
echo "Neutralizing ABI protected exports for Pixel compatibility..."
> common/android/abi_gki_protected_exports_aarch64
> common/android/abi_gki_protected_exports_x86_64

echo "=== Integrating KernelSU-Next ==="
echo "Cloning shoey63/KernelSU-Next..."
git clone https://github.com/shoey63/KernelSU-Next.git -b pixel9-susfs-gki-android14-6.1 KernelSU-Next

echo "Running KernelSU-Next setup..."
bash KernelSU-Next/kernel/setup.sh

echo "Restoring the custom pixel9-susfs branch..."
cd KernelSU-Next
git checkout pixel9-susfs-gki-android14-6.1
cd ..

echo "=== Integrating susfs4ksu ==="
echo "Cloning shoey63/susfs4ksu..."
git clone https://gitlab.com/shoey63/susfs4ksu.git -b gki-android14-6.1-dev susfs4ksu

echo "Copying susfs source files..."
cp -r susfs4ksu/kernel_patches/fs/* common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "Applying susfs kernel patches..."
cd common
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_*.patch .
patch -p1 < 50_add_susfs_in_*.patch || true

if [ -f "fs/namespace.c.rej" ]; then
    echo "Patch conflict detected in fs/namespace.c! Manually injecting susfs.h..."
    if ! grep -q "#include <linux/susfs.h>" fs/namespace.c; then
        sed -i '32i #include <linux/susfs.h>' fs/namespace.c
    fi
    rm -f fs/namespace.c.rej
fi
cd ..

echo "=== Configuring KSU & SUSFS for Kleaf ==="
# 1. Flip defaults in KSU Kconfig as per the susfs documentation
sed -i 's/default n/default y/g' KernelSU-Next/kernel/Kconfig || true

# 2. Force enable KSU and all SUSFS features directly in the GKI defconfig
GKI_DEFCONFIG="common/arch/arm64/configs/gki_defconfig"
echo "CONFIG_KSU=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> "$GKI_DEFCONFIG"
echo "CONFIG_KSU_SUSFS_SUS_SU=y" >> "$GKI_DEFCONFIG"

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Build Complete ==="
