# ZiggyDOS

A real 16-bit x86 DOS for the IBM PC.

ZiggyDOS is not a simulator, not an emulator front-end, and not a shell script.
It is a bootable operating system written in 16-bit x86 assembly:

* the BIOS loads a 512-byte boot sector from a real FAT12 volume,
* the boot sector loads the kernel into memory,
* the kernel takes over: it talks to the floppy controller through `INT 13h`,
  parses the FAT12 filesystem itself, implements a subset of the DOS API
  (`INT 21h`, `INT 20h`), runs an interactive command interpreter and loads
  and executes real `.COM` programs at `PSP:0100`.

Every command it runs — reading a file, creating a directory, copying a file —
changes the actual FAT and directory entries on the disk image. You can verify
that from the outside with stock tools such as `mdir` on Linux or plain DOS
`DIR`.

## What you get

| File | What it is |
| --- | --- |
| `build/ziggy-dos-144.img` | bootable 1.44 MB FAT12 floppy image (real BIOS boot) |
| `build/ziggy-dos.iso` | El Torito CD image; the BIOS boots the floppy image as drive A: |

Both images contain the same filesystem: the boot sector, the kernel (in the
reserved area of the volume), `README.TXT`, `TEST.TXT`, `DOCS\NOTES.TXT`
and `HELLO.COM`, a demo program that calls `INT 21h`.

Prebuilt images are checked in under `release/` — you can boot them without building anything.

## Quick start

```bash
# build everything (needs nasm, python3 and xorriso)
./build.sh

# run from the floppy image
qemu-system-i386 -drive file=build/ziggy-dos-144.img,format=raw,if=floppy -boot a

# run from the ISO
qemu-system-i386 -cdrom build/ziggy-dos.iso -boot d
```

On real hardware: write the `.img` to a 1.44 MB floppy (or to a USB drive with
a floppy-emulation bootloader) or burn the ISO to a CD and boot from it.

## Commands

```
DIR      list the current directory          TYPE     display a text file
COPY     copy a file                         DEL      delete a file
REN      rename a file                       MD       create a directory
RD       remove an empty directory           CD       change directory
CLS      clear the screen                    VER      show the version
DATE     show the date from the CMOS clock   TIME     show the time
ECHO     print text                          VOL      volume label
MEM      memory and disk information         HELP     command list
EXIT     reboot the machine
```

Anything else is treated as a program name: `HELLO` loads `HELLO.COM`,
builds a 256-byte PSP, places the image at `PSP:0100` and jumps to it. The
program returns with `RET` (the PSP starts with `INT 20h`) or with
`INT 21h / AH=4Ch`.

## Architecture

```
boot sector (LBA 0)          -> reads LBA 1..N into 8000:0000
  reserved sectors 1..N      -> the kernel itself (N = 1 + KSECTORS)
  FAT 1 / FAT 2              -> standard 12-bit FAT, two copies, both written
  root directory (224)       -> 14 sectors
  data area                  -> 1 sector per cluster, up to 2847 clusters
```

The kernel is stored in the volume's reserved area, so the boot sector does
not need a FAT parser: it reads consecutive sectors. The rest of the volume
is a completely ordinary FAT12 filesystem — `mdir`, Linux `mount` and DOS
itself read the same structures.

Memory map (real mode, 1 MB):

| Segment | Use |
| --- | --- |
| `0x8000` | kernel code, data, stack-independent state |
| `0x7F00` | kernel stack (SP = 0xFFFE) |
| `0x5000` | disk buffers: FAT, root directory, subdirectory, sector scratch |
| `0x1000` | program segment (PSP), programs load at `0x0100` |
| `0x0F00` | environment block (`PATH=A:\`) |
| `0x0060` | not touched; BIOS data area stays intact |

Kernel source layout:

```
src/boot.asm      boot sector, BPB, CHS/LBA reads, kernel load
src/kernel.asm    entry point and include list
src/console.asm   VGA text output, keyboard input, line editor
src/disk.asm      INT 13h driver, track/64K boundary splitting, retries
src/fat.asm       FAT12: mount, cluster chains, directories, read/write
src/path.asm      path resolution, 8.3 name conversion
src/dosapi.asm    INT 21h / INT 20h / INT 24h handlers
src/exec.asm      PSP construction, .COM loader
src/shell.asm     command interpreter and command table
src/cmds.asm      built-in commands
src/rtc.asm       CMOS real-time clock
src/data.asm      message strings and static data
```

The DOS API implements: `00 01 02 06 07 08 09 0A 0B 0C 19 1A 25 2A 2C 2F
30 35 36 3B 47 48 49 4A 4C`. File-handle calls (`3C 3D 3E 3F 40 41 42`)
are not implemented yet.

## Limitations

* no wildcards (`*.TXT`), no redirection, no batch files
* file-handle API missing; programs should use the FCB-free calls above
* the path is stored in a single 64-byte buffer
* 8.3 names only; long file names are ignored
* subdirectories hold at most 512 entries (16 KB directory buffer)
* `.COM` programs up to 0xFC00 bytes, no `.EXE` support
* the ISO is a CD: writes go to a RAM overlay in the emulated drive, so
  changes are not persistent there. Use the `.img` when you want to write.

## Verification

The build is tested in QEMU with both the floppy image and the ISO. The
session used for the screenshots below exercised `DIR`, `TYPE` (root and
subdirectory), `COPY`, `REN`, `DEL`, `MD`, `CD`, `RD`, `VER`, `MEM`, `DATE`,
`TIME` and `HELLO`. After running `COPY TEST.TXT ZZ.TXT` inside ZiggyDOS and
shutting the machine down, `mdir` on the host listed `ZZ.TXT` — the write
really happened on the FAT12 volume.

## License

MIT. See `LICENSE`.
