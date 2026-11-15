; =============================================================================
;  ZiggyDOS - real time clock access (CMOS)
;  DOS asks the BIOS; we go one level deeper and read the CMOS chip itself,
;  which is what a real DOS does when it wants the hardware clock.
; =============================================================================

rtc_wait:
    push ax
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jz .ready
.w:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jnz .w
.ready:
    pop ax
    ret

; in : AL = register, out: AL = value
rtc_read:
    out 0x70, al
    jmp short .delay
.delay:
    in al, 0x71
    ret

; in : AL = BCD, out: AL = binary
bcd_to_bin:
    push cx
    mov ch, al
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    mov cl, 10
    mul cl
    and ch, 0x0F
    add al, ch
    pop cx
    ret

; ---------------------------------------------------------------------------
;  rtc_get_time - out: CH = hour, CL = minute, DH = second
; ---------------------------------------------------------------------------
rtc_get_time:
    call rtc_wait
    push ax
    mov al, 0x00
    call rtc_read
    call bcd_to_bin
    mov dh, al
    pop ax
    push ax
    mov al, 0x02
    call rtc_read
    call bcd_to_bin
    mov cl, al
    pop ax
    push ax
    mov al, 0x04
    call rtc_read
    call bcd_to_bin
    mov ch, al
    pop ax
    ret

; ---------------------------------------------------------------------------
;  rtc_get_date - out: CX = year, DH = month, DL = day
; ---------------------------------------------------------------------------
rtc_get_date:
    call rtc_wait
    push ax
    mov al, 0x07
    call rtc_read
    call bcd_to_bin
    mov dl, al
    pop ax
    push ax
    mov al, 0x08
    call rtc_read
    call bcd_to_bin
    mov dh, al
    pop ax
    push ax
    mov al, 0x09
    call rtc_read
    call bcd_to_bin
    xor ah, ah
    mov bx, 2000
    add ax, bx
    mov cx, ax
    pop ax
    ret
