#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "[-] $*" >&2
  exit 1
}

info() {
  echo "[+] $*"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/boot_swap.sh --boot <boot.img> --image <Image> --magiskboot <magiskboot> --outdir <dir> [--outname <name>] [--workdir <dir>]

Required:
  --boot         Path to stock boot image
  --image        Path to replacement Image
  --magiskboot   Path to magiskboot binary
  --outdir       Output directory

Optional:
  --outname      Output filename (default: <boot-stem>-swapped.img)
  --workdir      Working directory base (default: <outdir>/work)
  -h, --help     Show this help
EOF
}

abspath() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

BOOT_IMG=""
IMAGE_FILE=""
MAGISKBOOT=""
OUTDIR=""
OUTNAME=""
WORKDIR_BASE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --boot)
      [ "$#" -ge 2 ] || die "Missing value for --boot"
      BOOT_IMG="$2"
      shift 2
      ;;
    --image)
      [ "$#" -ge 2 ] || die "Missing value for --image"
      IMAGE_FILE="$2"
      shift 2
      ;;
    --magiskboot)
      [ "$#" -ge 2 ] || die "Missing value for --magiskboot"
      MAGISKBOOT="$2"
      shift 2
      ;;
    --outdir)
      [ "$#" -ge 2 ] || die "Missing value for --outdir"
      OUTDIR="$2"
      shift 2
      ;;
    --outname)
      [ "$#" -ge 2 ] || die "Missing value for --outname"
      OUTNAME="$2"
      shift 2
      ;;
    --workdir)
      [ "$#" -ge 2 ] || die "Missing value for --workdir"
      WORKDIR_BASE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[ -n "$BOOT_IMG" ] || { usage; die "--boot is required"; }
[ -n "$IMAGE_FILE" ] || { usage; die "--image is required"; }
[ -n "$MAGISKBOOT" ] || { usage; die "--magiskboot is required"; }
[ -n "$OUTDIR" ] || { usage; die "--outdir is required"; }

BOOT_IMG="$(abspath "$BOOT_IMG")"
IMAGE_FILE="$(abspath "$IMAGE_FILE")"
MAGISKBOOT="$(abspath "$MAGISKBOOT")"
OUTDIR="$(abspath "$OUTDIR")"

if [ -n "$WORKDIR_BASE" ]; then
  WORKDIR_BASE="$(abspath "$WORKDIR_BASE")"
fi

[ -f "$BOOT_IMG" ] || die "Missing boot image: $BOOT_IMG"
[ -f "$IMAGE_FILE" ] || die "Missing Image: $IMAGE_FILE"
[ -x "$MAGISKBOOT" ] || die "magiskboot is not executable: $MAGISKBOOT"

mkdir -p "$OUTDIR"

if [ -z "$WORKDIR_BASE" ]; then
  WORKDIR_BASE="$OUTDIR/work"
fi
mkdir -p "$WORKDIR_BASE"

BOOT_BASENAME="$(basename "$BOOT_IMG")"
BOOT_STEM="${BOOT_BASENAME%.img}"

if [ -z "$OUTNAME" ]; then
  OUTNAME="${BOOT_STEM}-swapped.img"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$WORKDIR_BASE/swap-$TIMESTAMP"
mkdir -p "$RUN_DIR"

OUT_IMG="$OUTDIR/$OUTNAME"
LOG_FILE="$OUTDIR/boot_swap.log"
MAGISKBOOT_LOG="$OUTDIR/magiskboot.log"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

run_magiskboot() {
  local label="$1"
  shift

  {
    echo "========================================================================"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $label"
    echo "CMD: $*"
    echo "------------------------------------------------------------------------"
  } | tee -a "$MAGISKBOOT_LOG"

  if "$@" 2>&1 | tee -a "$MAGISKBOOT_LOG"; then
    echo >> "$MAGISKBOOT_LOG"
    return 0
  else
    echo >> "$MAGISKBOOT_LOG"
    die "$label failed (see $MAGISKBOOT_LOG)"
  fi
}

info "Stock boot    : $BOOT_IMG"
info "Replacement   : $IMAGE_FILE"
info "Magiskboot    : $MAGISKBOOT"
info "Temp run dir  : $RUN_DIR"
info "Output image  : $OUT_IMG"
info "Magiskboot log: $MAGISKBOOT_LOG"

cp -f "$BOOT_IMG" "$RUN_DIR/boot.img"
cp -f "$IMAGE_FILE" "$RUN_DIR/Image"
cp -f "$MAGISKBOOT" "$RUN_DIR/magiskboot"
chmod +x "$RUN_DIR/magiskboot"

cd "$RUN_DIR"

run_magiskboot "Unpacking boot image" ./magiskboot unpack boot.img

[ -f kernel ] || die "Unpacked kernel file not found"

info "Renaming stock kernel to kernel.stock..."
mv -f kernel kernel.stock || die "Failed to rename stock kernel"

info "Renaming Image to kernel..."
mv -f Image kernel || die "Failed to rename Image to kernel"

run_magiskboot "Repacking boot image" ./magiskboot repack boot.img

[ -f new-boot.img ] || die "new-boot.img was not produced"

if [ -e "$OUT_IMG" ]; then
  BASE="${OUT_IMG%.img}"
  OUT_IMG="${BASE}-${TIMESTAMP}.img"
fi

cp -f new-boot.img "$OUT_IMG"

STOCK_SHA="$(sha256_file "$BOOT_IMG")"
IMAGE_SHA="$(sha256_file "$IMAGE_FILE")"
OUT_SHA="$(sha256_file "$OUT_IMG")"

info "Done: $OUT_IMG"
echo
echo "[+] SHA256"
echo "    stock boot : $STOCK_SHA"
echo "    Image      : $IMAGE_SHA"
echo "    swapped    : $OUT_SHA"

{
  echo "========================================================================"
  echo "Timestamp     : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Stock boot    : $BOOT_IMG"
  echo "Image         : $IMAGE_FILE"
  echo "Magiskboot    : $MAGISKBOOT"
  echo "Output        : $OUT_IMG"
  echo "Stock SHA256  : $STOCK_SHA"
  echo "Image SHA256  : $IMAGE_SHA"
  echo "Output SHA256 : $OUT_SHA"
  echo "Magiskboot log: $MAGISKBOOT_LOG"
  echo
} >> "$LOG_FILE"

info "Log updated: $LOG_FILE"
info "Magiskboot log: $MAGISKBOOT_LOG"
