#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "[-] $*" >&2
  exit 1
}

info() {
  echo "[+] $*"
}

cd kernel_workspace
mkdir -p ../out

SUSFS_NEXT_URL="${SUSFS_NEXT_URL:-https://gitlab.com/pershoot/susfs4ksu.git}"
SUSFS_NEXT_REF="${SUSFS_NEXT_REF:-gki-android14-6.1-dev}"
SUSFS_NEXT_COMMIT="${SUSFS_NEXT_COMMIT:-}"

[ -d common ] || die "common/ not found in kernel_workspace"
[ -d KernelSU-Next/kernel ] || die "KernelSU-Next/kernel not found"

rm -rf susfs4ksu

info "Cloning pershoot susfs4ksu"
git clone --depth=1 -b "${SUSFS_NEXT_REF}" "${SUSFS_NEXT_URL}" susfs4ksu \
  > ../out/susfs_next_clone.log 2>&1 || {
  cat ../out/susfs_next_clone.log
  die "Failed to clone susfs4ksu"
}

if [ -n "${SUSFS_NEXT_COMMIT}" ]; then
  info "Checking out pinned susfs commit"
  git -C susfs4ksu fetch --depth=1 origin "${SUSFS_NEXT_COMMIT}" >> ../out/susfs_next_clone.log 2>&1 || {
    cat ../out/susfs_next_clone.log
    die "Failed to fetch pinned susfs commit ${SUSFS_NEXT_COMMIT}"
  }
  git -C susfs4ksu checkout --detach FETCH_HEAD >> ../out/susfs_next_clone.log 2>&1 || {
    cat ../out/susfs_next_clone.log
    die "Failed to checkout pinned susfs commit ${SUSFS_NEXT_COMMIT}"
  }
fi

find susfs4ksu/kernel_patches -maxdepth 3 -type f | sort \
  > ../out/susfs_next_patch_tree.txt || true

COMMON_PATCH_SRC="$(find susfs4ksu/kernel_patches -maxdepth 1 -type f -name '50_add_susfs_in_*.patch' | sort | head -n1 || true)"
[ -n "${COMMON_PATCH_SRC}" ] || die "Could not find 50_add_susfs_in_*.patch"

info "Skipping 10_enable_susfs_for_ksu.patch because dev-susfs already contains KSU-side SUSFS support"
echo "Skipped KSU-side SUSFS patch; using dev-susfs KSU tree" \
  > ../out/susfs_next_ksu_patch_skipped.txt

info "Common patch   : ${COMMON_PATCH_SRC}"

info "Copying SUSFS files into common/"
cp -f "${COMMON_PATCH_SRC}" common/
cp -rf susfs4ksu/kernel_patches/fs/* common/fs/
cp -rf susfs4ksu/kernel_patches/include/linux/* common/include/linux/

{
  echo "SUSFS_NEXT_URL=${SUSFS_NEXT_URL}"
  echo "SUSFS_NEXT_REF=${SUSFS_NEXT_REF}"
  echo "SUSFS_NEXT_COMMIT=${SUSFS_NEXT_COMMIT:-<none>}"
  echo "COMMON_PATCH_SRC=${COMMON_PATCH_SRC}"
} > ../out/susfs_next_integration_report.txt

{
  echo "=== common/fs susfs files ==="
  find common/fs -maxdepth 3 -type f | grep -i 'susfs' || true
  echo
  echo "=== common/include/linux susfs files ==="
  find common/include/linux -maxdepth 1 -type f | grep -i 'susfs' || true
} > ../out/susfs_next_copied_files.txt

if ! grep -q 'susfs_def.h' common/fs/namespace.c; then
  info "Applying manual fs/namespace.c include fix"
  sed -i '/#include <linux\/mnt_idmapping.h>/a\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux/susfs_def.h>\
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
' common/fs/namespace.c
fi

if ! grep -q 'susfs_mnt_id_ida' common/fs/namespace.c; then
  info "Applying manual fs/namespace.c SUSFS mount declarations fix"
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
' common/fs/namespace.c
fi

grep -n -A12 -B4 'susfs_def.h\|susfs_mnt_id_ida\|CL_COPY_MNT_NS\|internal.h' common/fs/namespace.c \
  > ../out/susfs_next_namespace_fix.txt || true

info "Dry-run common kernel patch"
set +e
(
  cd common
  patch -p1 --dry-run < "$(basename "${COMMON_PATCH_SRC}")"
) > ../out/susfs_next_common_dry_run.txt 2>&1
DRYRUN_RC=$?
set -e

if [ "$DRYRUN_RC" -ne 0 ]; then
  if grep -q "checking file fs/namespace.c" ../out/susfs_next_common_dry_run.txt &&
     grep -q "Hunk #1 FAILED at 32." ../out/susfs_next_common_dry_run.txt &&
     grep -q 'susfs_def.h' common/fs/namespace.c
  then
    info "Dry-run failure is expected: fs/namespace.c hunk #1 was manually pre-applied"
  else
    cat ../out/susfs_next_common_dry_run.txt
    die "Common kernel dry-run patch failed"
  fi
fi

info "Applying common kernel SUSFS patch"
set +e
(
  cd common
  patch -p1 < "$(basename "${COMMON_PATCH_SRC}")"
) > ../out/susfs_next_common_apply.txt 2>&1
APPLY_RC=$?
set -e

mapfile -t REJ_FILES < <(find common -type f -name '*.rej' | sort || true)

if [ "$APPLY_RC" -ne 0 ]; then
  if [ "${#REJ_FILES[@]}" -eq 1 ] &&
     [ "${REJ_FILES[0]}" = "common/fs/namespace.c.rej" ] &&
     grep -q 'susfs_def.h' common/fs/namespace.c
  then
    info "Apply failure is expected: fs/namespace.c hunk #1 was manually pre-applied"
    rm -f common/fs/namespace.c.rej
  else
    cat ../out/susfs_next_common_apply.txt
    die "Common kernel patch apply failed"
  fi
fi

find common -type f -name '*.rej' | sort > ../out/susfs_next_rejects.txt || true
if [ -s ../out/susfs_next_rejects.txt ]; then
  cat ../out/susfs_next_rejects.txt
  die "Patch reject(s) found; see out/susfs_next_rejects.txt"
fi

info "pershoot SUSFS common-side integration complete"
