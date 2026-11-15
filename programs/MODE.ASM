; =============================================================================
;  MODE.COM - report / set the video mode, as MS-DOS 6.22 does for the display
;  ZiggyDOS writes the screen itself, so only the 80x25 text modes are usable.
; =============================================================================
[BITS 16]
[ORG 0x100]

start:
    mov si, 0x81
    mov cl, [0x80]
    xor ch, ch
.skip:
    test cx, cx
    jz .show
    cmp byte [si], ' '
    jne .arg
    inc si
    dec cx
    jmp .skip
.arg:
    mov al, [si]
    cmp al, 'c'
    jb .uc
    cmp al, 'z'
    ja .uc
    sub al, 32
.uc:
    cmp al, '8'
    je .set80
    cmp al, '4'
    je .set40
    cmp al, 'C'
    je .co
    jmp .usage
.co:
    inc si
    dec cx
    test cx, cx
    jz .usage
    mov al, [si]
    and al, 0xDF
    cmp al, 'O'
    jne .usage
    inc si
    dec cx
    test cx, cx
    jz .usage
    mov al, [si]
    cmp al, '8'
    je .set80
    cmp al, '4'
    je .set40
    jmp .usage

.set80:
    mov ax, 0x0003                ; 80x25 16-colour text
    int 0x10
    mov dx, msg_set80
    call puts
    jmp .exit

.set40:
    mov dx, msg_set40
    call puts
    jmp .exit

.show:
    mov ah, 0x0F
    int 0x10
    mov [mode], al
    mov dx, msg_cur
    call puts
    mov al, [mode]
    cmp al, 0x03
    je .m80c
    cmp al, 0x07
    je .m80m
    cmp al, 0x01
    je .m40c
    cmp al, 0x00
    je .m40m
    mov dx, msg_other
    call puts
    jmp .exit
.m80c:
    mov dx, msg_80c
    call puts
    jmp .exit
.m80m:
    mov dx, msg_80m
    call puts
    jmp .exit
.m40c:
    mov dx, msg_40c
    call puts
    jmp .exit
.m40m:
    mov dx, msg_40m
    call puts
    jmp .exit

.usage:
    mov dx, msg_usage
    call puts
.exit:
    mov ax, 0x4C00
    int 0x21

puts:
    mov ah, 0x09
    int 0x21
    ret

mode db 0

msg_cur   db "Current mode: ", "$"
msg_80c   db "80x25/VGAtext", 13, 10, "$"
msg_80m   db "80x25/MDAtext", 13, 10, "$"
msg_40c   db "40x25/VGAtext", 13, 10, "$"
msg_40m   db "40x25/MDAtext", 13, 10, "$"
msg_other db "unknown video mode", 13, 10, "$"
msg_set80 db "Mode set to 80x25/VGAtext.", 13, 10
          db "The screen was cleared - type CLS to reset the shell.", 13, 10, "$"
msg_set40 db "MODE 40 is not available: ZiggyDOS drives the screen as fixed 80x25.", 13, 10, "$"
msg_usage db "Usage: MODE            show the current video mode", 13, 10
          db "       MODE 80|CO80    set 80x25/VGAtext", 13, 10, "$"
