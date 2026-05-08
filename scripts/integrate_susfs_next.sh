#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace

[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }

echo ">>> Cloning susfs4ksu..."
git clone --depth=1 -b "${SUSFS_NEXT_REF}" "${SUSFS_NEXT_URL}" susfs4ksu

COMMON_PATCH_SRC="$(find susfs4ksu/kernel_patches -maxdepth 1 -type f -name '50_add_susfs_in_*.patch' | head -n1)"
[ -n "${COMMON_PATCH_SRC}" ] || { echo "[-] Could not find 50_add_susfs_in_*.patch" >&2; exit 1; }

echo ">>> Copying SUSFS files into common/..."
cp -f "${COMMON_PATCH_SRC}" common/
cp -rf susfs4ksu/kernel_patches/fs/* common/fs/
cp -rf susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo ">>> Applying common kernel SUSFS patch..."
(cd common && patch -p1 --no-backup-if-mismatch < "$(basename "${COMMON_PATCH_SRC}")") || true

echo ">>> SUSFS common-side integration complete!"
