ZiggyDOS 0.10
=============

This is a real, bootable 16-bit DOS.  It is not a simulator and not a
shell script: the ISO contains a genuine FAT12 floppy image whose first
sector is a BIOS boot sector.  The BIOS loads it, it loads the kernel,
and the kernel is what is talking to your keyboard right now.

What is inside:
  * boot sector          loads the kernel from the reserved area
  * kernel               disk driver, FAT12, DOS API, command shell
  * HELLO.COM            a real .COM program, run through the loader

Try these:
  DIR
  TYPE README.TXT
  TYPE DOCS\NOTES.TXT
  HELLO
  COPY README.TXT COPY.TXT
  TYPE COPY.TXT
  DEL COPY.TXT
  MD WORK
  CD WORK
  CD ..
  VER
  MEM
  HELP

The volume is writable: COPY, DEL, MD and RD really change the FAT
and the directory entries on the disk image.
