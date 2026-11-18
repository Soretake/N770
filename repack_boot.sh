#!/bin/bash
# repack_boot.sh - build an OC boot.img by swapping the kernel in a stock boot.img
#
#   ./repack_boot.sh <stock_boot.img> <Image> [out_boot.img]
#
# Reuses the stock ramdisk + header (keeps the device bootable) and replaces only
# the kernel. Uses magiskboot (ships inside the Magisk app:
# /data/adb/magisk/magiskboot, or extract from the Magisk APK). magiskboot
# auto-detects Samsung's boot image format and any appended dtb/compression.
#
# After this, make the Odin tar:
#   tar -H ustar -cf N770-oc-2314.tar boot.img
# and flash boot.img as AP in Odin.
set -euo pipefail

STOCK="${1:?stock boot.img required}"
KIMG="${2:?kernel Image required}"
OUT="${3:-boot.img}"

MAGISKBOOT="${MAGISKBOOT:-$(command -v magiskboot || true)}"
if [ -z "$MAGISKBOOT" ]; then
  for c in /data/adb/magisk/magiskboot ./magiskboot; do
    [ -x "$c" ] && MAGISKBOOT="$c" && break
  done
fi
[ -n "$MAGISKBOOT" ] || { echo "ERROR: magiskboot not found (set MAGISKBOOT=/path)"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$STOCK" "$WORK/boot.img"
cp "$KIMG"  "$WORK/kernel.new"

( cd "$WORK"
  echo "== stock boot.img sha256 =="; sha256sum boot.img
  "$MAGISKBOOT" unpack boot.img
  cp kernel.new kernel            # replace only the kernel
  "$MAGISKBOOT" repack boot.img boot.new
)

cp "$WORK/boot.new" "$OUT"
echo "== OC boot.img written: $OUT =="
sha256sum "$OUT"
echo "Now: tar -H ustar -cf N770-oc-2314.tar $OUT"
