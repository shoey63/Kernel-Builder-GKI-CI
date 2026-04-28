#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace

[ -d common ] || { echo "[-] common/ not found in kernel_workspace" >&2; exit 1; }

# Variables (populated by GitHub Actions env block)
KSU_NEXT_SETUP_URL="${KSU_NEXT_SETUP_URL:-https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh}"
KSU_NEXT_REPO_URL="${KSU_NEXT_REPO_URL:-https://github.com/pershoot/KernelSU-Next.git}"
KSU_NEXT_REF="${KSU_NEXT_REF:-dev-susfs}"
KSU_NEXT_HOOK_MODE="${KSU_NEXT_HOOK_MODE:-}"

echo ">>> Fetching and running KernelSU-Next setup script..."
curl -LSs "$KSU_NEXT_SETUP_URL" -o /tmp/ksu_setup.sh
bash /tmp/ksu_setup.sh $KSU_NEXT_HOOK_MODE

# Detect which folder the setup script created
KSU_REPO=""
if [ -d KernelSU-Next/.git ]; then
  KSU_REPO="KernelSU-Next"
elif [ -d KernelSU/.git ]; then
  KSU_REPO="KernelSU"
else
  echo "[-] KernelSU repo not found after setup" >&2
  exit 1
fi

echo ">>> Forcing checkout to precise ref: ${KSU_NEXT_REF}..."
git -C "$KSU_REPO" fetch "$KSU_NEXT_REPO_URL" "$KSU_NEXT_REF" --depth=1
git -C "$KSU_REPO" checkout -B "$KSU_NEXT_REF" FETCH_HEAD

echo ">>> Creating symlink for Bazel sandbox..."
DRIVER_ROOT="common/drivers"
ln -sfn "../../${KSU_REPO}/kernel" "${DRIVER_ROOT}/kernelsu"

# Quick sanity check
[ -L "${DRIVER_ROOT}/kernelsu" ] || { echo "[-] Symlink failed" >&2; exit 1; }

echo ">>> KernelSU-Next integration complete!"
