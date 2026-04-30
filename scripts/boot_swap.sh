#!/usr/bin/env bash
set -euo pipefail

# Default variables
BOOT_IMG=""
IMAGE_FILE=""
MAGISKBOOT=""
OUTDIR=""
OUTNAME="swapped-boot.img"
WORKDIR="work/repack-tmp"

# Parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --boot) BOOT_IMG="$(realpath "$2")"; shift 2 ;;
    --image) IMAGE_FILE="$(realpath "$2")"; shift 2 ;;
    --magiskboot) MAGISKBOOT="$(realpath "$2")"; shift 2 ;;
    --outdir) OUTDIR="$(realpath "$2")"; shift 2 ;;
    --outname) OUTNAME="$2"; shift 2 ;;
    --workdir) WORKDIR="$(realpath "$2")"; shift 2 ;;
    *) echo "[-] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$BOOT_IMG" ] && [ -n "$IMAGE_FILE" ] && [ -n "$MAGISKBOOT" ] && [ -n "$OUTDIR" ] || \
  { echo "[-] Missing required arguments" >&2; exit 1; }

echo ">>> Setting up workspace..."
mkdir -p "$WORKDIR" "$OUTDIR"
cd "$WORKDIR"

echo ">>> Unpacking stock boot image..."
cp -f "$BOOT_IMG" boot.img
"$MAGISKBOOT" unpack boot.img || { echo "[-] Magiskboot unpack failed" >&2; exit 1; }

[ -f kernel ] || { echo "[-] Unpacked kernel not found" >&2; exit 1; }

echo ">>> Hot-swapping stock kernel with custom Image..."
cp -f "$IMAGE_FILE" kernel

echo ">>> Repacking new boot image..."
"$MAGISKBOOT" repack boot.img || { echo "[-] Magiskboot repack failed" >&2; exit 1; }

[ -f new-boot.img ] || { echo "[-] new-boot.img was not produced" >&2; exit 1; }

echo ">>> Saving final artifact..."
cp -f new-boot.img "$OUTDIR/$OUTNAME"

echo ">>> Boot swap complete! Artifact saved to: $OUTDIR/$OUTNAME"
