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

# --- HARD DEBUG TRAP ---
echo "Verifying Git state..."
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "pixel9-susfs-gki-android14-6.1" ]; then
    echo "CRITICAL ERROR: KernelSU-Next branch hijack detected!"
    echo "Currently on branch: $CURRENT_BRANCH"
    echo "Current commit:"
    git log -1
    exit 1
fi
echo "Git branch verified: $CURRENT_BRANCH. Proceeding."
cd ..

# Replace symlink with hard copy to bypass Bazel sandbox issues
echo "Replacing KSU symlink with a hard copy for the Bazel sandbox..."
rm -f common/drivers/kernelsu
cp -r KernelSU-Next/kernel common/drivers/kernelsu

# Strip config constraints
sed -i '/default [yn]/d' common/drivers/kernelsu/Kconfig || true
sed -i 's/^config .*/&\n\tdefault y/g' common/drivers/kernelsu/Kconfig || true

echo "=== Integrating susfs4ksu ==="
git clone https://gitlab.com/shoey63/susfs4ksu.git -b gki-android14-6.1-dev susfs4ksu

cp -r susfs4ksu/kernel_patches/fs/* common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "Applying susfs kernel patches..."
cd common
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_*.patch .
patch -p1 < 50_add_susfs_in_*.patch || true

# --- Unwrapped Manual Hunk #1 Fix ---
if ! grep -q 'susfs_def.h' fs/namespace.c; then
  echo "Applying manual fs/namespace.c include fix..."
  sed -i '/#include <linux\/mnt_idmapping.h>/a\
#include <linux/susfs_def.h>\
' fs/namespace.c
fi

# THE FIX: Look for the specific DEFINE_IDA declaration, not just the name!
if ! grep -q 'DEFINE_IDA(susfs_mnt_id_ida)' fs/namespace.c; then
  echo "Applying manual fs/namespace.c SUSFS mount declarations fix..."
  sed -i '/#include "internal.h"/a\
\
extern bool susfs_is_current_ksu_domain(void);\
extern struct static_key_false susfs_set_sdcard_android_data_decrypted_key_false;\
\
#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\
\
static DEFINE_IDA(susfs_mnt_id_ida);\
static DEFINE_IDA(susfs_mnt_group_ida);\
' fs/namespace.c
fi
rm -f fs/namespace.c.rej

cd ..

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Build Complete ==="
