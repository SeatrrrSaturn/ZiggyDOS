#!/bin/bash
# =============================================================================
#  build.sh - build ZiggyDOS from source into a bootable ISO
#
#  Requires: nasm, python3, xorriso
#  Output:   build/ziggy-dos-144.img  (bootable 1.44 MB floppy image)
#            build/ziggy-dos.iso      (El Torito CD image, boots as drive A:)
# =============================================================================
set -e
cd "$(dirname "$0")"

BUILD=build
SRC=src
ASSETS=assets
PROGRAMS=programs

mkdir -p "$BUILD"

echo "[1/5] assembling user programs"
for asm in "$PROGRAMS"/*.ASM; do
    [ -e "$asm" ] || continue
    base=$(basename "$asm" .ASM)
    nasm -f bin -o "$BUILD/$base.COM" "$asm"
    echo "      $base.COM  $(stat -c%s "$BUILD/$base.COM") bytes"
done
rm -rf "$BUILD/volume"
mkdir -p "$BUILD/volume"
cp -r "$ASSETS"/. "$BUILD/volume"/
cp "$BUILD"/*.COM "$BUILD/volume"/ 2>/dev/null || true

echo "[2/5] assembling the kernel"
nasm -f bin -I"$SRC" -o "$BUILD/kernel.bin" "$SRC/kernel.asm"
KSIZE=$(stat -c%s "$BUILD/kernel.bin")
KSECT=$(( (KSIZE + 511) / 512 ))
echo "      kernel.bin $KSIZE bytes ($KSECT sectors)"

echo "[3/5] assembling the boot sector"
nasm -f bin -I"$SRC" -DKSECTORS=$KSECT -o "$BUILD/boot.bin" "$SRC/boot.asm"
echo "      boot.bin   $(stat -c%s "$BUILD/boot.bin") bytes"

echo "[4/5] building the FAT12 floppy image"
python3 tools/mkimage.py "$BUILD/boot.bin" "$BUILD/kernel.bin" "$BUILD/ziggy-dos-144.img" "$BUILD/volume"

echo "[5/5] building the El Torito ISO"
rm -rf "$BUILD/iso_root"
mkdir -p "$BUILD/iso_root"
cp "$BUILD/ziggy-dos-144.img" "$BUILD/iso_root/"
cp assets/README.TXT "$BUILD/iso_root/README.TXT"
[ -f LICENSE ] && cp LICENSE "$BUILD/iso_root/LICENSE.TXT"
xorriso -as mkisofs \
    -V ZIGGYDOS -A "ZiggyDOS bootable ISO" -p "ZiggyDOS Project" \
    -R -J \
    -b ziggy-dos-144.img \
    -c boot.catalog \
    -o "$BUILD/ziggy-dos.iso" \
    "$BUILD/iso_root" 2>&1 | tail -3

ls -l "$BUILD/ziggy-dos-144.img" "$BUILD/ziggy-dos.iso"
echo "done."
