#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace

[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }

# Variables
KSU_NEXT_SETUP_URL="${KSU_NEXT_SETUP_URL:-https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh}"
KSU_NEXT_REPO_URL="${KSU_NEXT_REPO_URL:-https://github.com/pershoot/KernelSU-Next.git}"
KSU_NEXT_REF="${KSU_NEXT_REF:-dev-susfs}"
KSU_NEXT_HOOK_MODE="${KSU_NEXT_HOOK_MODE:-}"

echo "=== Integrating KernelSU-Next ==="
# 1. Clone Repo
git clone "${KSU_NEXT_REPO_URL}" -b "${KSU_NEXT_REF}" KernelSU-Next

# 2. Run setup
bash KernelSU-Next/kernel/setup.sh

# 3. Check Branch
CURRENT_BRANCH=$(git -C KernelSU-Next branch --show-current)

if [ "$CURRENT_BRANCH" != "${KSU_NEXT_REF}" ]; then
    echo ">>> setup.sh hijacked the branch (currently on: $CURRENT_BRANCH). Restoring ${KSU_NEXT_REF} branch..."
    git -C KernelSU-Next checkout "${KSU_NEXT_REF}"
else
    echo ">>> Branch is intact"
fi

# 4. Symlink
echo ">>> Creating symlink for Bazel sandbox..."
ln -sfn ../../KernelSU-Next/kernel common/drivers/kernelsu

# Quick sanity check
[ -L "${DRIVER_ROOT}/kernelsu" ] || { echo "[-] Symlink failed" >&2; exit 1; }

echo ">>> KernelSU-Next integration complete!"
