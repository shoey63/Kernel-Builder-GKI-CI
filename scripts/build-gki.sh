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

# --- User's Manual Hunk #1 Fix ---
if ! grep -q 'susfs_def.h' fs/namespace.c; then
  echo "Applying manual fs/namespace.c include fix..."
  sed -i '/#include <linux\/mnt_idmapping.h>/a\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux/susfs_def.h>\
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
' fs/namespace.c
fi

if ! grep -q 'susfs_mnt_id_ida' fs/namespace.c; then
  echo "Applying manual fs/namespace.c SUSFS mount declarations fix..."
  sed -i '/#include "internal.h"/a\
\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
extern bool susfs_is_current_ksu_domain(void);\
extern struct static_key_false susfs_set_sdcard_android_data_decrypted_key_false;\
\
#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\
\
static DEFINE_IDA(susfs_mnt_id_ida);\
static DEFINE_IDA(susfs_mnt_group_ida);\
\
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
' fs/namespace.c
fi
# Clean up the rejection file so the build area stays clean
rm -f fs/namespace.c.rej
cd ..

echo "=== Configuring KSU & SUSFS for Kleaf ==="
sed -i '/default [yn]/d' KernelSU-Next/kernel/Kconfig || true
sed -i 's/^config .*/&\n\tdefault y/g' KernelSU-Next/kernel/Kconfig || true

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Build Complete ==="
