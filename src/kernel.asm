; =============================================================================
;  ZiggyDOS kernel
; ---------------------------------------------------------------------------
;  Loaded by the boot sector at 8000:0000 in 16-bit real mode.
;  Owns the BIOS disk driver, the FAT12 filesystem, the DOS interrupt
;  services, the command interpreter and the .COM loader.
; =============================================================================

[BITS 16]
[ORG 0x0000]

%include "include/defs.inc"

    jmp kernel_entry

%include "console.asm"
%include "scrollback.asm"
%include "disk.asm"
%include "rtc.asm"
%include "fat.asm"
%include "path.asm"
%include "dosapi.asm"
%include "exec.asm"
%include "shell.asm"
%include "cmds.asm"
%include "cmds2.asm"
%include "data.asm"

; ---------------------------------------------------------------------------
kernel_entry:
    cli
    cld
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, 0xFFFE
    mov ax, cs
    mov ds, ax
    mov es, ax
    sti
    mov [disk_drive], dl

    mov ax, 0x0003                ; 80x25 colour text mode, cursor home
    int 0x10

    mov si, msg_banner
    call puts

    call fat_init
    jc .no_filesystem
    call setup_environment
    call install_vectors

    mov si, msg_ready
    call puts
    jmp shell

.no_filesystem:
    mov si, msg_no_fs
    call puts
.hang:
    hlt
    jmp .hang
