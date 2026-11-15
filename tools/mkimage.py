#!/usr/bin/env python3
"""
mkimage.py - build a real, mountable FAT12 1.44 MB floppy image.

The boot sector and the kernel live in the reserved area of the volume
(the boot sector says how many reserved sectors there are), so the filesystem
itself starts at the first FAT and is completely standard: Linux, Windows,
mtools and the ZiggyDOS kernel all read the same on-disk structures.
"""

import os
import struct
import sys

SECTOR = 512
TOTAL_SECTORS = 2880
FATS = 2
FAT_SECS = 9
ROOT_ENTS = 224
ROOT_SECS = ROOT_ENTS * 32 // SECTOR
SPC = 1

# 2026-11-15 13:00:00 in FAT format
FAT_DATE = ((2026 - 1980) << 9) | (11 << 5) | 15
FAT_TIME = (13 << 11) | (0 << 5) | 0


def fat_set(fat, cluster, value):
    off = cluster * 3 // 2
    if cluster & 1:
        fat[off] = (fat[off] & 0x0F) | ((value & 0x0F) << 4)
        fat[off + 1] = (value >> 4) & 0xFF
    else:
        fat[off] = value & 0xFF
        fat[off + 1] = (fat[off + 1] & 0xF0) | ((value >> 8) & 0x0F)


def dirent(name, ext, attr, cluster, size, first_byte=None):
    e = bytearray(32)
    n = name.upper().ljust(8)[:8]
    x = ext.upper().ljust(3)[:3]
    e[0:8] = n.encode('ascii')
    e[8:11] = x.encode('ascii')
    e[11] = attr
    e[13] = 0
    e[14:16] = struct.pack('<H', FAT_TIME)
    e[16:18] = struct.pack('<H', FAT_DATE)
    e[18:20] = struct.pack('<H', FAT_DATE)
    e[20:22] = struct.pack('<H', 0)
    e[22:24] = struct.pack('<H', FAT_TIME)
    e[24:26] = struct.pack('<H', FAT_DATE)
    e[26:28] = struct.pack('<H', cluster & 0xFFFF)
    e[28:32] = struct.pack('<I', size)
    if first_byte is not None:
        e[0] = first_byte
    return bytes(e)


class Volume:
    def __init__(self, boot, kernel):
        self.img = bytearray(TOTAL_SECTORS * SECTOR)
        self.img[0:SECTOR] = boot
        self.ksec = (len(kernel) + SECTOR - 1) // SECTOR
        self.img[SECTOR:SECTOR + len(kernel)] = kernel

        self.reserved = struct.unpack('<H', boot[0x0E:0x10])[0]
        if self.reserved != 1 + self.ksec:
            raise SystemExit("boot sector reserved-sector count does not match the kernel size")

        self.fat_start = self.reserved
        self.root_start = self.fat_start + FATS * FAT_SECS
        self.data_start = self.root_start + ROOT_SECS
        self.max_cluster = (TOTAL_SECTORS - self.data_start) // SPC

        self.fat = bytearray(FAT_SECS * SECTOR)
        self.fat[0:3] = bytes([0xF0, 0xFF, 0xFF])
        self.next_cluster = 2

    # ------------------------------------------------------------------
    def alloc(self):
        c = self.next_cluster
        if c > self.max_cluster + 1:
            raise SystemExit("image is full")
        self.next_cluster += 1
        fat_set(self.fat, c, 0xFFF)
        return c

    def cluster_lba(self, c):
        return self.data_start + (c - 2) * SPC

    def write_data(self, data):
        """Store data in a cluster chain, return the first cluster."""
        if not data:
            return 0
        first = None
        prev = None
        pos = 0
        while pos < len(data):
            c = self.alloc()
            if first is None:
                first = c
            if prev is not None:
                fat_set(self.fat, prev, c)
            prev = c
            lba = self.cluster_lba(c)
            chunk = data[pos:pos + SPC * SECTOR]
            self.img[lba * SECTOR:lba * SECTOR + len(chunk)] = chunk
            pos += SPC * SECTOR
        return first

    def write_dir(self, cluster, entries):
        """Write a directory cluster (cluster 0 means the root directory)."""
        if cluster == 0:
            base = self.root_start * SECTOR
            capacity = ROOT_SECS * SECTOR
        else:
            base = self.cluster_lba(cluster) * SECTOR
            capacity = SPC * SECTOR
        if len(entries) > capacity:
            raise SystemExit("directory does not fit")
        for i, e in enumerate(entries):
            self.img[base + i * 32:base + i * 32 + 32] = e

    def add_file(self, entries, name, ext, data, attr=0x20):
        cluster = self.write_data(data)
        entries.append(dirent(name, ext, attr, cluster, len(data)))
        return cluster

    def finalize(self, out_path):
        for i in range(FATS):
            off = (self.fat_start + i * FAT_SECS) * SECTOR
            self.img[off:off + len(self.fat)] = self.fat
        with open(out_path, 'wb') as f:
            f.write(self.img)
        return len(self.img)


def split_name(filename):
    if '.' in filename:
        base, ext = filename.rsplit('.', 1)
    else:
        base, ext = filename, ''
    return base, ext


def main():
    if len(sys.argv) < 4:
        print("usage: mkimage.py <boot.bin> <kernel.bin> <out.img> [assets_dir]")
        return 1

    boot = open(sys.argv[1], 'rb').read()
    kernel = open(sys.argv[2], 'rb').read()
    out = sys.argv[3]
    assets = sys.argv[4] if len(sys.argv) > 4 else None
    if len(boot) != SECTOR:
        raise SystemExit("boot sector must be exactly 512 bytes")

    vol = Volume(boot, kernel)

    # root directory: volume label first, then files and subdirectories
    root = [dirent('ZIGGYDOS', '', 0x08, 0, 0)]

    subdirs = []
    if assets and os.path.isdir(assets):
        for entry in sorted(os.listdir(assets)):
            path = os.path.join(assets, entry)
            if os.path.isdir(path):
                subdirs.append(entry)
            else:
                data = open(path, 'rb').read()
                base, ext = split_name(entry)
                vol.add_file(root, base, ext, data)
                print("  + %-14s %6d bytes" % (entry, len(data)))

    for d in subdirs:
        path = os.path.join(assets, d)
        entries = [
            dirent('.', '', 0x10, 0, 0),
            dirent('..', '', 0x10, 0, 0),
        ]
        cluster = vol.alloc()
        for f in sorted(os.listdir(path)):
            fp = os.path.join(path, f)
            if os.path.isdir(fp):
                continue
            data = open(fp, 'rb').read()
            base, ext = split_name(f)
            vol.add_file(entries, base, ext, data)
            print("  + %s/%s  %d bytes" % (d, f, len(data)))
        # patch "." and ".." clusters
        entries[0] = dirent('.', '', 0x10, cluster, 0)
        entries[1] = dirent('..', '', 0x10, 0, 0)
        vol.write_dir(cluster, entries)
        root.append(dirent(d, '', 0x10, cluster, 0))

    vol.write_dir(0, root)
    size = vol.finalize(out)
    print("volume: %s (%d bytes, %d clusters, %d reserved sectors)"
          % (out, size, vol.max_cluster, vol.reserved))
    return 0


if __name__ == '__main__':
    sys.exit(main())
