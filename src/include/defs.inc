; =============================================================================
;  ZiggyDOS - shared definitions
; =============================================================================

; --- kernel load / segment layout --------------------------------------------
%define KERNEL_SEG      0x8000      ; this kernel lives at 8000:0000
%define STACK_SEG       0x7F00      ; 16 KiB stack, grows down from 7F00:FFFE
%define PSP_SEG         0x1000      ; first program segment (PSP at 1000:0000)
%define PROG_TOP_SEG    0x4FFF      ; top of the program arena
%define MEM_TOP_SEG     0x9FFF      ; conventional memory top (640 KiB)
%define ENV_SEG         0x0F00      ; environment block for child programs

; --- system buffers (all inside segment 0x5000) ------------------------------
%define BUF_SEG         0x5000
%define FAT_OFF         0x0000      ; 4608 bytes, one FAT (9 sectors)
%define ROOT_OFF        0x1200      ; 7168 bytes, 224 root entries
%define DIR_OFF         0x3000      ; 16384 bytes, scratch directory buffer
%define DIR_SIZE        0x4000
%define SEC_OFF         0x7000      ; 512 bytes, single sector scratch

%define SECTOR_SIZE     512
%define DIRENT_SIZE     32

; --- FAT attribute bits ------------------------------------------------------
%define ATTR_READONLY   0x01
%define ATTR_HIDDEN     0x02
%define ATTR_SYSTEM     0x04
%define ATTR_VOLUME     0x08
%define ATTR_DIR        0x10
%define ATTR_ARCHIVE    0x20
%define ATTR_LFN        0x0F

; --- DOS version reported by INT 21h AH=30h ----------------------------------
%define DOS_MAJOR       3
%define DOS_MINOR       30
