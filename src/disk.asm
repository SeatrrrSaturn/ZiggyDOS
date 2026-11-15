; =============================================================================
;  ZiggyDOS - BIOS disk access
;  Everything below 0x10000 goes straight through INT 13h, so the driver
;  works on a real floppy controller exactly as it does in QEMU.
; =============================================================================

; ---------------------------------------------------------------------------
;  disk_reset - recalibrate / reset the controller
; ---------------------------------------------------------------------------
disk_reset:
    push ax
    push dx
    xor ax, ax
    mov dl, [disk_drive]
    int 0x13
    pop dx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  disk_read / disk_write
;    in : AX = start LBA, CX = sector count, ES:BX = buffer
;    out: CF = 0 on success, CF = 1 on failure
;  Transfers are split at track boundaries and never cross a 64 KiB
;  segment boundary, which is what real BIOS implementations require.
; ---------------------------------------------------------------------------
disk_read:
    mov si, 0x02                 ; BIOS "read sectors"
    jmp disk_rw
disk_write:
    mov si, 0x03                 ; BIOS "write sectors"
disk_rw:
    mov [disk_op], si
    mov [disk_lba], ax
    mov [disk_rem], cx
    mov [disk_bseg], es
    mov [disk_boff], bx

.chunk:
    mov cx, [disk_rem]
    test cx, cx
    jz .success

    ; --- LBA to CHS -----------------------------------------------------
    mov ax, [disk_lba]
    xor dx, dx
    mov bx, [disk_spt]
    div bx                       ; ax = track, dx = lba % sectors-per-track
    mov cl, dl
    inc cl                       ; sector number, 1..spt
    xor dx, dx
    mov bx, [disk_heads]
    div bx                       ; ax = cylinder, dx = head
    mov ch, al
    mov dh, dl

    ; --- sectors remaining on this track --------------------------------
    mov al, [disk_spt]
    sub al, cl
    inc al
    xor ah, ah
    cmp ax, [disk_rem]
    jbe .have_count
    mov ax, [disk_rem]
.have_count:

    ; --- keep the transfer inside one segment ---------------------------
.fit:
    mov bx, ax
    shl bx, 9
    add bx, [disk_boff]
    jnc .fits
    dec ax
    jmp .fit
.fits:
    mov [disk_chunk], ax

    ; --- do it, with retries --------------------------------------------
    mov bp, 5
.retry:
    mov al, [disk_chunk]
    mov ah, [disk_op]
    mov bx, [disk_boff]
    mov es, [disk_bseg]
    mov dl, [disk_drive]
    int 0x13
    jnc .done_chunk
    push ax
    call disk_reset
    pop ax
    dec bp
    jnz .retry
    stc
    ret

.done_chunk:
    mov ax, [disk_chunk]
    add [disk_lba], ax
    sub [disk_rem], ax
    mov bx, [disk_boff]
    shl ax, 9
    add bx, ax
    mov [disk_boff], bx
    jnc .chunk
    mov ax, [disk_bseg]
    add ax, 0x1000
    mov [disk_bseg], ax
    jmp .chunk

.success:
    clc
    ret

; ---------------------------------------------------------------------------
disk_drive   db 0
disk_op      db 0
disk_lba     dw 0
disk_rem     dw 0
disk_chunk   dw 0
disk_bseg    dw 0
disk_boff    dw 0
disk_spt     dw 18
disk_heads   dw 2
