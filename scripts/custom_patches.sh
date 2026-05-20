#!/usr/bin/env bash
set -e

# Force KPM injection for SukiSU-Ultra
if [ "$ROOT_MANAGER" = "SukiSU-Ultra" ]; then
    echo ">>> SukiSU-Ultra detected! Forcing KPM via compiler override..."
    
    # Custom patches script runs from the repository root, so we need the full path
    KSU_DIR="kernel_workspace/common/drivers/kernelsu"
    [ -d "kernel_workspace/common/fs/ksu" ] && KSU_DIR="kernel_workspace/common/fs/ksu"
    
    # 1. Pass the flag directly to the C compiler for this directory only
    echo "ccflags-y += -DCONFIG_KPM" >> "$KSU_DIR/Makefile"
    
    # 2. Ensure the Makefile traverses into the kpm/ folder
    grep -q "obj-y += kpm/" "$KSU_DIR/Makefile" || echo "obj-y += kpm/" >> "$KSU_DIR/Makefile"
fi

# ---------------------------------------------------------
# CUSTOM PATCHES & CHERRY-PICKS
# ---------------------------------------------------------
# This script runs AFTER 'repo sync' but BEFORE 'build_kernel.sh'.
# Use it to modify the source tree (Makefile, Kconfig, etc.)
# ---------------------------------------------------------

# Example: 
# cd kernel_workspace/common
# git fetch https://android.googlesource.com/kernel/common <branch>
# git cherry-pick <hash>
# cd ../..

# echo ">>> User modifications complete."
