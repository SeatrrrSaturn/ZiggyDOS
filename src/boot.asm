; =============================================================================
;  ZiggyDOS - boot sector
;  ---------------------------------------------------------------------------
;  A real 16-bit x86 boot sector for a 1.44 MB FAT12 floppy image.
;  It carries a standard BPB (so the image is a genuine FAT12 volume that
;   DOS, Linux, mtools and Windows can all mount), and it loads the kernel
;  from the reserved area (LBA 1 .. 1+KSECTORS-1) to 8000:0000.
;
;  Boot drive number is passed on to the kernel in DL.
;  Assembled with: nasm -f bin -DKSECTORS=<n> -o boot.bin boot.asm
; =============================================================================

[BITS 16]
[ORG 0x7C00]

%ifndef KSECTORS
%define KSECTORS 64
%endif

%macro BDBG 1
%ifdef DEBUG
    push ax
    mov al, %1
    out 0xE9, al
    pop ax
%endif
%endmacro

; ---------------------------------------------------------------------------
;  BPB / BIOS parameter block  (offsets fixed by the FAT specification)
; ---------------------------------------------------------------------------
    jmp short begin
    nop

OEMName     db "ZIGGYDOS"        ; 8 bytes, offset 0x03
BytesPerSec dw 512               ; 0x0B
SecPerClus  db 1                 ; 0x0D
ReservedSec dw 1 + KSECTORS      ; 0x0E  boot sector + kernel
NumFATs     db 2                 ; 0x10
RootEntries dw 224               ; 0x11
TotalSec16  dw 2880              ; 0x13  1.44 MB
MediaDesc   db 0xF0              ; 0x15
FATSize     dw 9                 ; 0x16  sectors per FAT
SecPerTrack dw 18                ; 0x18
NumHeads    dw 2                 ; 0x1A
HiddenSec   dd 0                 ; 0x1C
TotalSec32  dd 0                 ; 0x20
DriveNum    db 0                 ; 0x24
Reserved1   db 0                 ; 0x25
BootSig     db 0x29              ; 0x26  extended boot signature
VolSerial   dd 0x5A49364B        ; 0x27  'ZI6K'
VolLabel    db "ZIGGYDOS   "     ; 0x2B  11 bytes
FileSysType db "FAT12   "        ; 0x36  8 bytes

; ---------------------------------------------------------------------------
begin:
    BDBG 'B'
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov [boot_drive], dl

    BDBG 'R'
    mov si, msg_loading
    call print

    mov si, 1                    ; first LBA of the kernel
    mov di, KSECTORS             ; sector count
    mov ax, 0x8000
    mov es, ax
    xor bx, bx
    call read_range

    BDBG 'K'
    mov si, msg_ok
    call print

    mov dl, [boot_drive]
    BDBG 'J'
    push 0x8000
    push 0x0000
    retf

; ---------------------------------------------------------------------------
;  print - write the zero terminated string at DS:SI via BIOS teletype
; ---------------------------------------------------------------------------
print:
    push ax
    push bx
    push si
.next:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .next
.done:
    pop si
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  read_range
;    in:  SI = start LBA, DI = sector count, ES:BX = destination
;    out: all sectors loaded, or the machine halts with a message
;  Reads one track run at a time, retrying three times per run.
; ---------------------------------------------------------------------------
read_range:
.loop:
    test di, di
    jz .done

    ; --- LBA -> CHS ------------------------------------------------------
    mov ax, si
    xor dx, dx
    mov bp, [SecPerTrack]
    div bp                       ; ax = lba/18, dx = lba%18
    mov cl, dl
    inc cl                       ; sector number 1..18
    xor dx, dx
    mov bp, [NumHeads]
    div bp                       ; ax = cylinder, dx = head
    mov ch, al
    mov dh, dl

    ; --- sectors left on this track --------------------------------------
    mov al, [SecPerTrack]
    sub al, cl
    inc al
    xor ah, ah
    cmp ax, di
    jbe .have_count
    mov ax, di
.have_count:
    mov [io_count], ax

    ; --- never let the transfer cross a 64 KiB boundary -------------------
.fit:
    mov ax, [io_count]
    shl ax, 9
    add ax, bx                   ; CX must keep CL = sector number
    jnc .fits
    dec word [io_count]
    jmp .fit
.fits:

    ; --- perform the read, with retries ----------------------------------
    mov bp, 4
.retry:
    mov al, [io_count]
    mov ah, 0x02                 ; BIOS: read sectors
    mov dl, [boot_drive]
    int 0x13
    jnc .ok
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13                     ; reset the controller
    dec bp
    jnz .retry
    mov si, msg_error
    call print
.halt:
    cli
    hlt
    jmp .halt
.ok:
    mov ax, [io_count]
    add si, ax                   ; advance LBA
    sub di, ax                   ; consume sector count
    shl ax, 9
    add bx, ax                   ; advance destination
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
boot_drive  db 0
io_count    dw 0

msg_loading db "ZiggyDOS: loading kernel...", 13, 10, 0
msg_ok      db "kernel loaded, starting system", 13, 10, 0
msg_error   db 13, 10, "Boot read error - system halted", 13, 10, 0

; ---------------------------------------------------------------------------
    times 510 - ($ - $$) db 0
    dw 0xAA55
