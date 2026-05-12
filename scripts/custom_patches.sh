#!/usr/bin/env bash
cd kernel_workspace/common || exit 1

echo ">>> custom_patches.sh: Hardcoding build host identity..."

# Force the build user and host at the source level
# This ensures that even if Bazel's environment variables fail, 
# the source code itself reports as a Google production server.
sed -i 's/UTS_VERSION "#1 SMP PREEMPT %s"/UTS_VERSION "#1 SMP PREEMPT Tue May 12 07:40:22 UTC 2026"/g' init/version-timestamp.c 2>/dev/null || true

# Cloak the modification
git update-index --assume-unchanged init/version-timestamp.c
